// SPDX-License-Identifier: MIT
#include "wayembed.h"
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/gui/iwaylandframe.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivsthostapplication.h"
#include "public.sdk/source/main/pluginfactory.h"

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <poll.h>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>
#include <wayland-client.h>

using namespace Steinberg;
using namespace Steinberg::Vst;

extern "C" {

struct nilrack_wayland_handles {
    uint32_t size;
    void *display;
    void *compositor;
    void *subcompositor;
    void *shm;
    void *seat;
    void *xdg_wm_base;
    void *parent_surface;
};

struct nilrack_vst3_ui;

int32_t nilrack_vst3_ui_create(const char *bundle_path,
                               const nilrack_wayland_handles *handles,
                               int32_t width,
                               int32_t height,
                               nilrack_vst3_ui **out_ui);
int32_t nilrack_vst3_ui_pump(nilrack_vst3_ui *ui);
int32_t nilrack_vst3_ui_resize(nilrack_vst3_ui *ui, int32_t width, int32_t height);
void nilrack_vst3_ui_destroy(nilrack_vst3_ui *ui);
}

static bool sameIid(const TUID a, const TUID b)
{
    return std::memcmp(a, b, sizeof(TUID)) == 0;
}

static void logError(const char *message)
{
    std::fprintf(stderr, "nilrack-vst3-ui: %s\n", message);
}

class HostApp;
class PlugFrame;

struct nilrack_vst3_ui {
    nilrack_wayland_handles handles = {};
    wayembed_server *server = nullptr;
    wayembed_client *client = nullptr;
    wayembed_embed *embed = nullptr;
    wl_display *pluginDisplay = nullptr;
    wl_surface *child = nullptr;
    wl_proxy *parentProxy = nullptr;
    uint32_t adoptStatus = WAYEMBED_EMBED_STATUS_INVALID_ARGUMENT;
    int connected = 0;
    int closed = 0;
    int surfaceCreated = 0;
    int mapped = 0;
    int resized = 0;

    void *module = nullptr;
    bool moduleEntered = false;
    IPluginFactory *factory = nullptr;
    IEditController *controller = nullptr;
    IPlugView *view = nullptr;
    HostApp *hostApp = nullptr;
    PlugFrame *frame = nullptr;
};

static wl_display *hostDisplay(nilrack_vst3_ui *ui)
{
    return static_cast<wl_display *>(ui->handles.display);
}

static wl_surface *hostParentSurface(nilrack_vst3_ui *ui)
{
    return static_cast<wl_surface *>(ui->handles.parent_surface);
}

static wl_compositor *hostCompositor(void *userdata)
{
    return static_cast<wl_compositor *>(static_cast<nilrack_vst3_ui *>(userdata)->handles.compositor);
}

static wl_subcompositor *hostSubcompositor(void *userdata)
{
    return static_cast<wl_subcompositor *>(static_cast<nilrack_vst3_ui *>(userdata)->handles.subcompositor);
}

static wl_shm *hostShm(void *userdata)
{
    return static_cast<wl_shm *>(static_cast<nilrack_vst3_ui *>(userdata)->handles.shm);
}

static wl_seat *hostSeat(void *userdata)
{
    return static_cast<wl_seat *>(static_cast<nilrack_vst3_ui *>(userdata)->handles.seat);
}

static xdg_wm_base *hostXdgWmBase(void *userdata)
{
    return static_cast<xdg_wm_base *>(static_cast<nilrack_vst3_ui *>(userdata)->handles.xdg_wm_base);
}

static bool hostSubsurfaceOffset(void *, int32_t *x, int32_t *y, wl_display *, wl_surface *, wl_surface *)
{
    if (x) {
        *x = 32;
    }
    if (y) {
        *y = 32;
    }
    return true;
}

static void onClientConnected(void *userdata, wayembed_client *client)
{
    auto *ui = static_cast<nilrack_vst3_ui *>(userdata);
    ui->connected++;
    ui->client = client;
}

static void onClientClosed(void *userdata, wayembed_client *)
{
    static_cast<nilrack_vst3_ui *>(userdata)->closed++;
}

static void onSurfaceCreated(void *userdata, wayembed_client *client, wl_surface *surface)
{
    auto *ui = static_cast<nilrack_vst3_ui *>(userdata);
    ui->surfaceCreated++;
    ui->client = client;
    ui->child = surface;
}

static void onEmbedMapped(void *userdata, wayembed_embed *embed)
{
    if (embed && wayembed_embed_id(embed) != 0) {
        auto *ui = static_cast<nilrack_vst3_ui *>(userdata);
        ui->mapped++;
    }
}

static void onEmbedResized(void *userdata, wayembed_embed *embed, int32_t width, int32_t height)
{
    if (embed && wayembed_embed_id(embed) != 0 && width > 0 && height > 0) {
        static_cast<nilrack_vst3_ui *>(userdata)->resized++;
    }
}

class HostApp final : public IHostApplication, public IWaylandHost, public Linux::IRunLoop {
public:
    explicit HostApp(wayembed_server *serverIn) : server(serverIn) {}
    ~HostApp()
    {
        if (timerHandler) {
            timerHandler->release();
            timerHandler = nullptr;
        }
    }

    wl_display *prepareWaylandConnection()
    {
        preparedDisplay = wayembed_server_open_client_display(server);
        return preparedDisplay;
    }

    tresult PLUGIN_API queryInterface(const TUID queryIid, void **obj) SMTG_OVERRIDE
    {
        if (!obj) {
            return kInvalidArgument;
        }
        if (sameIid(queryIid, INLINE_UID_OF(IHostApplication)) ||
            sameIid(queryIid, INLINE_UID_OF(FUnknown))) {
            *obj = static_cast<IHostApplication *>(this);
        } else if (sameIid(queryIid, INLINE_UID_OF(IWaylandHost))) {
            *obj = static_cast<IWaylandHost *>(this);
        } else if (sameIid(queryIid, INLINE_UID_OF(Linux::IRunLoop))) {
            *obj = static_cast<Linux::IRunLoop *>(this);
        } else {
            *obj = nullptr;
            return kNoInterface;
        }
        addRef();
        return kResultOk;
    }

    uint32 PLUGIN_API addRef() SMTG_OVERRIDE { return ++refs; }
    uint32 PLUGIN_API release() SMTG_OVERRIDE { return refs > 1 ? --refs : refs; }

    tresult PLUGIN_API getName(String128 name) SMTG_OVERRIDE
    {
        if (!name) {
            return kInvalidArgument;
        }
        const char *text = "nilrack";
        for (size_t i = 0; i < 128; i++) {
            name[i] = i < std::strlen(text) ? static_cast<TChar>(text[i]) : 0;
        }
        return kResultOk;
    }

    tresult PLUGIN_API createInstance(TUID cid, TUID iid, void **obj) SMTG_OVERRIDE
    {
        if (!obj) {
            return kInvalidArgument;
        }
        *obj = nullptr;
        if (sameIid(cid, INLINE_UID_OF(IWaylandHost)) &&
            sameIid(iid, INLINE_UID_OF(IWaylandHost))) {
            *obj = static_cast<IWaylandHost *>(this);
            addRef();
            return kResultOk;
        }
        return kNoInterface;
    }

    wl_display *PLUGIN_API openWaylandConnection() SMTG_OVERRIDE
    {
        if (preparedDisplay) {
            activeDisplays.push_back(preparedDisplay);
            wl_display *result = preparedDisplay;
            preparedDisplay = nullptr;
            return result;
        }
        wl_display *display = wayembed_server_open_client_display(server);
        if (display) {
            activeDisplays.push_back(display);
        }
        return display;
    }

    tresult PLUGIN_API closeWaylandConnection(wl_display *display) SMTG_OVERRIDE
    {
        if (!display) {
            return kInvalidArgument;
        }
        activeDisplays.erase(std::remove(activeDisplays.begin(), activeDisplays.end(), display),
                             activeDisplays.end());
        return wayembed_server_close_client_display(server, display) ? kResultOk : kResultFalse;
    }

    tresult PLUGIN_API registerEventHandler(Linux::IEventHandler *, Linux::FileDescriptor) SMTG_OVERRIDE
    {
        return kResultTrue;
    }

    tresult PLUGIN_API unregisterEventHandler(Linux::IEventHandler *) SMTG_OVERRIDE
    {
        return kResultTrue;
    }

    tresult PLUGIN_API registerTimer(Linux::ITimerHandler *handler, Linux::TimerInterval) SMTG_OVERRIDE
    {
        if (!handler) {
            return kInvalidArgument;
        }
        if (timerHandler) {
            timerHandler->release();
        }
        timerHandler = handler;
        timerHandler->addRef();
        return kResultTrue;
    }

    tresult PLUGIN_API unregisterTimer(Linux::ITimerHandler *handler) SMTG_OVERRIDE
    {
        if (timerHandler && (!handler || timerHandler == handler)) {
            timerHandler->release();
            timerHandler = nullptr;
        }
        return kResultTrue;
    }

    void fireTimers()
    {
        if (timerHandler) {
            timerHandler->onTimer();
        }
    }

private:
    wayembed_server *server = nullptr;
    wl_display *preparedDisplay = nullptr;
    std::vector<wl_display *> activeDisplays;
    Linux::ITimerHandler *timerHandler = nullptr;
    uint32 refs = 1;
};

class PlugFrame final : public IPlugFrame, public IWaylandFrame {
public:
    PlugFrame(wl_surface *parentIn, wl_proxy *parentProxyIn)
        : parent(parentIn), parentProxy(parentProxyIn)
    {
    }

    tresult PLUGIN_API queryInterface(const TUID queryIid, void **obj) SMTG_OVERRIDE
    {
        if (!obj) {
            return kInvalidArgument;
        }
        if (sameIid(queryIid, INLINE_UID_OF(IPlugFrame)) ||
            sameIid(queryIid, INLINE_UID_OF(FUnknown))) {
            *obj = static_cast<IPlugFrame *>(this);
        } else if (sameIid(queryIid, INLINE_UID_OF(IWaylandFrame))) {
            *obj = static_cast<IWaylandFrame *>(this);
        } else {
            *obj = nullptr;
            return kNoInterface;
        }
        addRef();
        return kResultOk;
    }

    uint32 PLUGIN_API addRef() SMTG_OVERRIDE { return ++refs; }
    uint32 PLUGIN_API release() SMTG_OVERRIDE { return refs > 1 ? --refs : refs; }

    tresult PLUGIN_API resizeView(IPlugView *view, ViewRect *newSize) SMTG_OVERRIDE
    {
        return view && newSize ? view->onSize(newSize) : kInvalidArgument;
    }

    wl_surface *PLUGIN_API getWaylandSurface(wl_display *) SMTG_OVERRIDE
    {
        return reinterpret_cast<wl_surface *>(parentProxy ? parentProxy : reinterpret_cast<wl_proxy *>(parent));
    }

    xdg_surface *PLUGIN_API getParentSurface(ViewRect &, wl_display *) SMTG_OVERRIDE
    {
        return nullptr;
    }

    xdg_toplevel *PLUGIN_API getParentToplevel(wl_display *) SMTG_OVERRIDE
    {
        return nullptr;
    }

private:
    wl_surface *parent = nullptr;
    wl_proxy *parentProxy = nullptr;
    uint32 refs = 1;
};

static int32_t pumpOnce(nilrack_vst3_ui *ui, int timeoutMs)
{
    if (!ui || !ui->server) {
        return 1;
    }
    if (ui->pluginDisplay) {
        wl_display_flush(ui->pluginDisplay);
    }
    wayembed_server_dispatch(ui->server);
    wayembed_server_flush(ui->server);
    if (hostDisplay(ui)) {
        wl_display_flush(hostDisplay(ui));
    }

    pollfd fds[2] = {};
    fds[0].fd = wayembed_server_get_fd(ui->server);
    fds[0].events = POLLIN;
    fds[1].fd = ui->pluginDisplay ? wl_display_get_fd(ui->pluginDisplay) : -1;
    fds[1].events = ui->pluginDisplay ? POLLIN : 0;
    const int nfds = ui->pluginDisplay ? 2 : 1;
    const int result = poll(fds, nfds, timeoutMs);
    if (result < 0) {
        return 2;
    }
    if (fds[0].revents & POLLIN) {
        wayembed_server_dispatch(ui->server);
    }
    if (ui->pluginDisplay && (fds[1].revents & POLLIN)) {
        if (wl_display_dispatch(ui->pluginDisplay) < 0) {
            return 3;
        }
    } else if (ui->pluginDisplay) {
        wl_display_dispatch_pending(ui->pluginDisplay);
    }
    if (ui->hostApp) {
        ui->hostApp->fireTimers();
    }
    wayembed_server_flush(ui->server);
    return 0;
}

static void pumpServerOnly(nilrack_vst3_ui *ui, const std::atomic<bool> *stop)
{
    if (!ui || !ui->server || !stop) {
        return;
    }
    while (!stop->load(std::memory_order_relaxed)) {
        wayembed_server_dispatch(ui->server);
        wayembed_server_flush(ui->server);
        if (hostDisplay(ui)) {
            wl_display_flush(hostDisplay(ui));
        }

        pollfd fd = {wayembed_server_get_fd(ui->server), POLLIN, 0};
        if (poll(&fd, 1, 2) > 0 && (fd.revents & POLLIN)) {
            wayembed_server_dispatch(ui->server);
        }
    }
    wayembed_server_dispatch(ui->server);
    wayembed_server_flush(ui->server);
}

static int32_t pumpClientOnly(nilrack_vst3_ui *ui, int timeoutMs)
{
    if (!ui || !ui->pluginDisplay) {
        return 1;
    }
    wl_display_flush(ui->pluginDisplay);
    wl_display_dispatch_pending(ui->pluginDisplay);

    pollfd fd = {wl_display_get_fd(ui->pluginDisplay), POLLIN, 0};
    const int result = poll(&fd, 1, timeoutMs);
    if (result < 0) {
        return 2;
    }
    if (fd.revents & POLLIN) {
        if (wl_display_dispatch(ui->pluginDisplay) < 0) {
            return 3;
        }
    }
    if (ui->hostApp) {
        ui->hostApp->fireTimers();
    }
    return 0;
}

static uint32_t tryAdoptSubsurface(nilrack_vst3_ui *ui)
{
    wayembed_embed_attach_info info = {};
    info.size = sizeof(info);
    info.version = WAYEMBED_ABI_VERSION;
    info.client = ui->client;
    info.parent_surface = hostParentSurface(ui);
    info.child_surface = ui->child;
    ui->adoptStatus = wayembed_embed_adopt_subsurface(&info, &ui->embed);
    return ui->adoptStatus;
}

static bool waitForAdoptedSubsurface(nilrack_vst3_ui *ui, int timeoutMs)
{
    int remaining = timeoutMs;
    while (remaining > 0 && !ui->embed) {
        if (pumpClientOnly(ui, 20) != 0) {
            return false;
        }
        remaining -= 20;
        if (ui->client && ui->child) {
            const uint32_t status = tryAdoptSubsurface(ui);
            if (status == WAYEMBED_EMBED_STATUS_OK) {
                pumpClientOnly(ui, 20);
                return true;
            }
            if (status != WAYEMBED_EMBED_STATUS_UNKNOWN_SURFACE) {
                return false;
            }
        }
    }
    return ui->embed != nullptr;
}

static bool validHandles(const nilrack_wayland_handles *handles)
{
    return handles && handles->size >= sizeof(nilrack_wayland_handles) && handles->display &&
           handles->compositor && handles->subcompositor && handles->shm && handles->parent_surface;
}

static void cleanup(nilrack_vst3_ui *ui)
{
    if (!ui) {
        return;
    }
    if (ui->view) {
        (void)ui->view->removed();
        ui->view->release();
        ui->view = nullptr;
    }
    if (ui->frame) {
        delete ui->frame;
        ui->frame = nullptr;
    }
    if (ui->parentProxy && ui->server) {
        wayembed_server_destroy_proxy(ui->server, ui->parentProxy);
        ui->parentProxy = nullptr;
    }
    if (ui->controller) {
        ui->controller->terminate();
        ui->controller->release();
        ui->controller = nullptr;
    }
    if (ui->factory) {
        ui->factory->release();
        ui->factory = nullptr;
    }
    if (ui->hostApp) {
        delete ui->hostApp;
        ui->hostApp = nullptr;
    }
    if (ui->moduleEntered) {
        using ModuleExitFn = bool (*)(void);
        auto moduleExit = reinterpret_cast<ModuleExitFn>(dlsym(ui->module, "ModuleExit"));
        if (moduleExit) {
            (void)moduleExit();
        }
        ui->moduleEntered = false;
    }
    if (ui->module) {
        (void)dlclose(ui->module);
        ui->module = nullptr;
    }
    if (ui->server) {
        wayembed_server_destroy(ui->server);
        ui->server = nullptr;
    }
}

extern "C" int32_t nilrack_vst3_ui_create(const char *bundle_path,
                                           const nilrack_wayland_handles *handles,
                                           int32_t width,
                                           int32_t height,
                                           nilrack_vst3_ui **out_ui)
{
    if (out_ui) {
        *out_ui = nullptr;
    }
    if (!out_ui || !bundle_path || width <= 0 || height <= 0 || !validHandles(handles)) {
        return 1;
    }

    auto *ui = new nilrack_vst3_ui();
    ui->handles = *handles;

    wayembed_host_interface host = {};
    host.size = sizeof(host);
    host.version = WAYEMBED_ABI_VERSION;
    host.userdata = ui;
    host.get_compositor = hostCompositor;
    host.get_subcompositor = hostSubcompositor;
    host.get_shm = hostShm;
    host.get_seat = hostSeat;
    host.get_xdg_wm_base = hostXdgWmBase;
    host.get_subsurface_offset = hostSubsurfaceOffset;
    host.on_client_connected = onClientConnected;
    host.on_client_closed = onClientClosed;
    host.on_surface_created = onSurfaceCreated;
    host.on_embed_mapped = onEmbedMapped;
    host.on_embed_resized = onEmbedResized;

    ui->server = wayembed_server_create(&host, nullptr);
    if (!ui->server) {
        logError("wayembed_server_create failed");
        delete ui;
        return 2;
    }

    ui->hostApp = new HostApp(ui->server);
    ui->pluginDisplay = ui->hostApp->prepareWaylandConnection();
    if (!ui->pluginDisplay) {
        logError("failed to open plugin Wayland display");
        cleanup(ui);
        delete ui;
        return 3;
    }
    wayembed_server_dispatch(ui->server);

    ui->parentProxy = wayembed_server_create_proxy(
        ui->server, ui->pluginDisplay, reinterpret_cast<wl_proxy *>(hostParentSurface(ui)));
    if (!ui->parentProxy || wl_proxy_get_display(ui->parentProxy) != ui->pluginDisplay) {
        logError("failed to create plugin-display parent proxy");
        cleanup(ui);
        delete ui;
        return 4;
    }

    const std::string libraryPath =
        std::string(bundle_path) + "/Contents/x86_64-linux/nilamp-twd-mkii.so";
    ui->module = dlopen(libraryPath.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!ui->module) {
        std::fprintf(stderr, "nilrack-vst3-ui: dlopen failed: %s\n", dlerror());
        cleanup(ui);
        delete ui;
        return 5;
    }

    using ModuleEntryFn = bool (*)(void *);
    using GetFactoryFn = IPluginFactory *(*)();
    auto moduleEntry = reinterpret_cast<ModuleEntryFn>(dlsym(ui->module, "ModuleEntry"));
    auto getFactory = reinterpret_cast<GetFactoryFn>(dlsym(ui->module, "GetPluginFactory"));
    if (!moduleEntry || !getFactory || !moduleEntry(ui->module)) {
        logError("missing or failed VST3 module entry points");
        cleanup(ui);
        delete ui;
        return 6;
    }
    ui->moduleEntered = true;

    ui->factory = getFactory();
    if (!ui->factory) {
        logError("missing VST3 factory");
        cleanup(ui);
        delete ui;
        return 7;
    }

    IPluginFactory3 *factory3 = nullptr;
    if (ui->factory->queryInterface(INLINE_UID_OF(IPluginFactory3),
                                    reinterpret_cast<void **>(&factory3)) == kResultOk) {
        (void)factory3->setHostContext(
            static_cast<FUnknown *>(static_cast<IHostApplication *>(ui->hostApp)));
        factory3->release();
    }

    TUID controllerUid = INLINE_UID(0x66e72a3a, 0x9187500d, 0xafa4d86a, 0x88935c65);
    if (ui->factory->createInstance(controllerUid, INLINE_UID_OF(IEditController),
                                    reinterpret_cast<void **>(&ui->controller)) != kResultOk ||
        !ui->controller) {
        logError("nilamp edit controller create failed");
        cleanup(ui);
        delete ui;
        return 8;
    }
    if (ui->controller->initialize(static_cast<FUnknown *>(static_cast<IHostApplication *>(ui->hostApp))) !=
        kResultOk) {
        logError("nilamp edit controller initialize failed");
        cleanup(ui);
        delete ui;
        return 9;
    }

    ui->view = ui->controller->createView(ViewType::kEditor);
    if (!ui->view ||
        ui->view->isPlatformTypeSupported(kPlatformTypeWaylandSurfaceID) != kResultTrue) {
        logError("nilamp editor does not support WaylandSurfaceID");
        cleanup(ui);
        delete ui;
        return 10;
    }

    ViewRect preferredRect(0, 0, width, height);
    if (ui->view->getSize(&preferredRect) == kResultOk &&
        preferredRect.getWidth() > 0 && preferredRect.getHeight() > 0) {
        width = preferredRect.getWidth();
        height = preferredRect.getHeight();
    }

    ui->frame = new PlugFrame(hostParentSurface(ui), ui->parentProxy);
    ViewRect rect(0, 0, width, height);
    std::atomic<bool> stopAttachPump{false};
    std::thread attachPump(pumpServerOnly, ui, &stopAttachPump);
    if (ui->view->setFrame(ui->frame) != kResultOk || ui->view->onSize(&rect) != kResultOk ||
        ui->view->attached(ui->parentProxy, kPlatformTypeWaylandSurfaceID) != kResultOk) {
        stopAttachPump.store(true, std::memory_order_relaxed);
        attachPump.join();
        logError("nilamp WaylandSurfaceID attach failed");
        cleanup(ui);
        delete ui;
        return 11;
    }

    if (!waitForAdoptedSubsurface(ui, 1000) || !ui->embed || ui->mapped < 1) {
        stopAttachPump.store(true, std::memory_order_relaxed);
        attachPump.join();
        logError("wayembed subsurface adoption failed");
        cleanup(ui);
        delete ui;
        return 12;
    }
    if (wayembed_embed_resize(ui->embed, width, height) != WAYEMBED_EMBED_STATUS_OK) {
        stopAttachPump.store(true, std::memory_order_relaxed);
        attachPump.join();
        logError("initial embed resize failed");
        cleanup(ui);
        delete ui;
        return 13;
    }
    stopAttachPump.store(true, std::memory_order_relaxed);
    attachPump.join();

    std::fprintf(stderr,
                 "nilrack-vst3-ui: mapped nilamp editor connected=%d surfaces=%d mapped=%d size=%dx%d\n",
                 ui->connected,
                 ui->surfaceCreated,
                 ui->mapped,
                 width,
                 height);
    *out_ui = ui;
    return 0;
}

extern "C" int32_t nilrack_vst3_ui_pump(nilrack_vst3_ui *ui)
{
    return pumpOnce(ui, 0);
}

extern "C" int32_t nilrack_vst3_ui_resize(nilrack_vst3_ui *ui, int32_t width, int32_t height)
{
    if (!ui || !ui->embed || width <= 0 || height <= 0) {
        return 1;
    }
    ViewRect rect(0, 0, width, height);
    if (ui->view) {
        (void)ui->view->onSize(&rect);
    }
    return wayembed_embed_resize(ui->embed, width, height) == WAYEMBED_EMBED_STATUS_OK ? 0 : 2;
}

extern "C" void nilrack_vst3_ui_destroy(nilrack_vst3_ui *ui)
{
    cleanup(ui);
    delete ui;
}
