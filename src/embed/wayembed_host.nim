{.passC: "-I/home/niltempus/dev/wayembed/zig-out/include".}

const
  WayembedAbiVersion* = 2'u32
  WayembedEmbedStatusOk* = 0'u32

type
  WlCompositor* {.importc: "struct wl_compositor", header: "wayembed.h".} = object
  WlDisplay* {.importc: "struct wl_display", header: "wayembed.h".} = object
  WlEventQueue* {.importc: "struct wl_event_queue", header: "wayembed.h".} = object
  WlProxy* {.importc: "struct wl_proxy", header: "wayembed.h".} = object
  WlSeat* {.importc: "struct wl_seat", header: "wayembed.h".} = object
  WlShm* {.importc: "struct wl_shm", header: "wayembed.h".} = object

  WlSubcompositor* {.importc: "struct wl_subcompositor", header: "wayembed.h".} = object
  WlSurface* {.importc: "struct wl_surface", header: "wayembed.h".} = object
  XdgWmBase* {.importc: "struct xdg_wm_base", header: "wayembed.h".} = object

  LinuxDmabuf* {.importc: "struct zwp_linux_dmabuf_v1", header: "wayembed.h".} = object

  WayembedServer* {.importc: "wayembed_server", header: "wayembed.h".} = object
  WayembedClient* {.importc: "wayembed_client", header: "wayembed.h".} = object
  WayembedEmbed* {.importc: "wayembed_embed", header: "wayembed.h".} = object

  WayembedOutputInfo* {.bycopy, importc: "wayembed_output_info", header: "wayembed.h".} = object
    size*: uint32
    version*: uint32
    x*: int32
    y*: int32
    physicalWidth* {.importc: "physical_width".}: int32
    physicalHeight* {.importc: "physical_height".}: int32
    subpixel*: int32
    make*: cstring
    model*: cstring
    transform*: int32
    modeFlags* {.importc: "mode_flags".}: uint32
    modeWidth* {.importc: "mode_width".}: int32
    modeHeight* {.importc: "mode_height".}: int32
    modeRefresh* {.importc: "mode_refresh".}: int32
    scale*: int32
    name*: cstring
    description*: cstring

  WayembedAttachInfo* {.
    bycopy, importc: "wayembed_embed_attach_info", header: "wayembed.h"
  .} = object
    size*: uint32
    version*: uint32
    client*: ptr WayembedClient
    parentSurface* {.importc: "parent_surface".}: ptr WlSurface
    childSurface* {.importc: "child_surface".}: ptr WlSurface

  WayembedHostInterface* {.
    bycopy, importc: "wayembed_host_interface", header: "wayembed.h"
  .} = object
    size*: uint32
    version*: uint32
    userdata*: pointer
    getCompositor* {.importc: "get_compositor".}:
      proc(userdata: pointer): ptr WlCompositor {.cdecl, raises: [].}
    getSubcompositor* {.importc: "get_subcompositor".}:
      proc(userdata: pointer): ptr WlSubcompositor {.cdecl, raises: [].}
    getShm* {.importc: "get_shm".}:
      proc(userdata: pointer): ptr WlShm {.cdecl, raises: [].}
    getSeat* {.importc: "get_seat".}:
      proc(userdata: pointer): ptr WlSeat {.cdecl, raises: [].}
    getXdgWmBase* {.importc: "get_xdg_wm_base".}:
      proc(userdata: pointer): ptr XdgWmBase {.cdecl, raises: [].}
    getDmabuf* {.importc: "get_dmabuf".}:
      proc(userdata: pointer): ptr LinuxDmabuf {.cdecl, raises: [].}
    getSubsurfaceOffset* {.importc: "get_subsurface_offset".}: proc(
      userdata: pointer,
      x: ptr int32,
      y: ptr int32,
      display: ptr WlDisplay,
      parent: ptr WlSurface,
      child: ptr WlSurface,
    ): bool {.cdecl, raises: [].}
    onClientConnected* {.importc: "on_client_connected".}:
      proc(userdata: pointer, client: ptr WayembedClient) {.cdecl, raises: [].}
    onSurfaceCreated* {.importc: "on_surface_created".}: proc(
      userdata: pointer, client: ptr WayembedClient, childSurface: ptr WlSurface
    ) {.cdecl, raises: [].}
    onClientClosed* {.importc: "on_client_closed".}:
      proc(userdata: pointer, client: ptr WayembedClient) {.cdecl, raises: [].}
    onProtocolError* {.importc: "on_protocol_error".}: proc(
      userdata: pointer, client: ptr WayembedClient, code: uint32
    ) {.cdecl, raises: [].}
    onEmbedMapped* {.importc: "on_embed_mapped".}:
      proc(userdata: pointer, embed: ptr WayembedEmbed) {.cdecl, raises: [].}
    onEmbedResized* {.importc: "on_embed_resized".}: proc(
      userdata: pointer, embed: ptr WayembedEmbed, width, height: int32
    ) {.cdecl, raises: [].}
    onEmbedDestroyed* {.importc: "on_embed_destroyed".}:
      proc(userdata: pointer, embed: ptr WayembedEmbed) {.cdecl, raises: [].}
    getSeatCapabilities* {.importc: "get_seat_capabilities".}:
      proc(userdata: pointer): uint32 {.cdecl, raises: [].}
    getSeatName* {.importc: "get_seat_name".}:
      proc(userdata: pointer): cstring {.cdecl, raises: [].}
    getOutputInfo* {.importc: "get_output_info".}:
      proc(userdata: pointer, info: ptr WayembedOutputInfo): bool {.cdecl, raises: [].}

  WayembedHostHandles* = object
    compositor*: pointer
    subcompositor*: pointer
    shm*: pointer
    seat*: pointer
    xdgWmBase*: pointer
    parentSurface*: pointer

  WayembedHost* = object
    handles*: WayembedHostHandles
    cInterface*: WayembedHostInterface
    server*: ptr WayembedServer
    client*: ptr WayembedClient
    embed*: ptr WayembedEmbed
    childSurface*: pointer
    mapped*: bool
    closed*: bool
    failed*: bool
    protocolErrorCode*: uint32
    width*: int32
    height*: int32

proc wayembedServerCreate(
  host: ptr WayembedHostInterface, queue: ptr WlEventQueue
): ptr WayembedServer {.importc: "wayembed_server_create", header: "wayembed.h".}

proc wayembedServerDestroy*(
  server: ptr WayembedServer
) {.importc: "wayembed_server_destroy", header: "wayembed.h".}

proc wayembedServerGetFd*(
  server: ptr WayembedServer
): int32 {.importc: "wayembed_server_get_fd", header: "wayembed.h".}

proc wayembedServerDispatch*(
  server: ptr WayembedServer
) {.importc: "wayembed_server_dispatch", header: "wayembed.h".}

proc wayembedServerFlush*(
  server: ptr WayembedServer
) {.importc: "wayembed_server_flush", header: "wayembed.h".}

proc wayembedServerOpenClientDisplay*(
  server: ptr WayembedServer
): ptr WlDisplay {.
  importc: "wayembed_server_open_client_display", header: "wayembed.h"
.}

proc wayembedServerCloseClientDisplay*(
  server: ptr WayembedServer, display: ptr WlDisplay
): bool {.importc: "wayembed_server_close_client_display", header: "wayembed.h".}

proc wayembedServerOpenClientFd*(
  server: ptr WayembedServer, outClient: ptr ptr WayembedClient
): int32 {.importc: "wayembed_server_open_client_fd", header: "wayembed.h".}

proc wayembedServerCloseClient*(
  server: ptr WayembedServer, client: ptr WayembedClient
): bool {.importc: "wayembed_server_close_client", header: "wayembed.h".}

proc wayembedServerCreateProxy*(
  server: ptr WayembedServer, clientDisplay: ptr WlDisplay, hostObject: ptr WlProxy
): ptr WlProxy {.importc: "wayembed_server_create_proxy", header: "wayembed.h".}

proc wayembedServerDestroyProxy*(
  server: ptr WayembedServer, proxy: ptr WlProxy
) {.importc: "wayembed_server_destroy_proxy", header: "wayembed.h".}

proc wayembedEmbedAttach(
  info: ptr WayembedAttachInfo, outEmbed: ptr ptr WayembedEmbed
): uint32 {.importc: "wayembed_embed_attach", header: "wayembed.h".}

proc wayembedEmbedAdoptSubsurface(
  info: ptr WayembedAttachInfo, outEmbed: ptr ptr WayembedEmbed
): uint32 {.importc: "wayembed_embed_adopt_subsurface", header: "wayembed.h".}

proc wayembedEmbedResize*(
  embed: ptr WayembedEmbed, width, height: int32
): uint32 {.importc: "wayembed_embed_resize", header: "wayembed.h".}

proc getHost(userdata: pointer): ptr WayembedHost {.inline.} =
  cast[ptr WayembedHost](userdata)

proc hostCompositor(userdata: pointer): ptr WlCompositor {.cdecl, raises: [].} =
  cast[ptr WlCompositor](userdata.getHost().handles.compositor)

proc hostSubcompositor(userdata: pointer): ptr WlSubcompositor {.cdecl, raises: [].} =
  cast[ptr WlSubcompositor](userdata.getHost().handles.subcompositor)

proc hostShm(userdata: pointer): ptr WlShm {.cdecl, raises: [].} =
  cast[ptr WlShm](userdata.getHost().handles.shm)

proc hostSeat(userdata: pointer): ptr WlSeat {.cdecl, raises: [].} =
  cast[ptr WlSeat](userdata.getHost().handles.seat)

proc hostXdgWmBase(userdata: pointer): ptr XdgWmBase {.cdecl, raises: [].} =
  cast[ptr XdgWmBase](userdata.getHost().handles.xdgWmBase)

proc hostDmabuf(userdata: pointer): ptr LinuxDmabuf {.cdecl, raises: [].} =
  discard userdata
  nil

proc hostSubsurfaceOffset(
    userdata: pointer,
    x: ptr int32,
    y: ptr int32,
    display: ptr WlDisplay,
    parent: ptr WlSurface,
    child: ptr WlSurface,
): bool {.cdecl, raises: [].} =
  discard userdata
  discard display
  discard parent
  discard child
  if not x.isNil:
    x[] = 0
  if not y.isNil:
    y[] = 0
  true

proc hostClientConnected(
    userdata: pointer, client: ptr WayembedClient
) {.cdecl, raises: [].} =
  userdata.getHost().client = client

proc hostSurfaceCreated(
    userdata: pointer, client: ptr WayembedClient, childSurface: ptr WlSurface
) {.cdecl, raises: [].} =
  let host = userdata.getHost()
  host.client = client
  host.childSurface = cast[pointer](childSurface)

proc hostClientClosed(
    userdata: pointer, client: ptr WayembedClient
) {.cdecl, raises: [].} =
  let host = userdata.getHost()
  if host.client == client:
    host.client = nil
  host.closed = true

proc hostProtocolError(
    userdata: pointer, client: ptr WayembedClient, code: uint32
) {.cdecl, raises: [].} =
  discard client
  let host = userdata.getHost()
  host.failed = true
  host.protocolErrorCode = code

proc hostEmbedMapped(
    userdata: pointer, embed: ptr WayembedEmbed
) {.cdecl, raises: [].} =
  let host = userdata.getHost()
  host.embed = embed
  host.mapped = true

proc hostEmbedResized(
    userdata: pointer, embed: ptr WayembedEmbed, width, height: int32
) {.cdecl, raises: [].} =
  let host = userdata.getHost()
  host.embed = embed
  host.width = width
  host.height = height

proc hostEmbedDestroyed(
    userdata: pointer, embed: ptr WayembedEmbed
) {.cdecl, raises: [].} =
  let host = userdata.getHost()
  if host.embed == embed:
    host.embed = nil
  host.mapped = false

proc hostSeatCapabilities(userdata: pointer): uint32 {.cdecl, raises: [].} =
  discard userdata
  0

proc hostOutputInfo(
    userdata: pointer, info: ptr WayembedOutputInfo
): bool {.cdecl, raises: [].} =
  discard userdata
  discard info
  false

proc initWayembedHostInterface*(host: var WayembedHost) =
  host.cInterface = WayembedHostInterface(
    size: uint32(sizeof(WayembedHostInterface)),
    version: WayembedAbiVersion,
    userdata: addr host,
    getCompositor: hostCompositor,
    getSubcompositor: hostSubcompositor,
    getShm: hostShm,
    getSeat: hostSeat,
    getXdgWmBase: hostXdgWmBase,
    getDmabuf: hostDmabuf,
    getSubsurfaceOffset: hostSubsurfaceOffset,
    onClientConnected: hostClientConnected,
    onSurfaceCreated: hostSurfaceCreated,
    onClientClosed: hostClientClosed,
    onProtocolError: hostProtocolError,
    onEmbedMapped: hostEmbedMapped,
    onEmbedResized: hostEmbedResized,
    onEmbedDestroyed: hostEmbedDestroyed,
    getSeatCapabilities: hostSeatCapabilities,
    getOutputInfo: hostOutputInfo,
  )

proc initWayembedHost*(host: var WayembedHost, handles: WayembedHostHandles): bool =
  host = WayembedHost(handles: handles)
  host.initWayembedHostInterface()
  host.server = wayembedServerCreate(addr host.cInterface, nil)
  host.server != nil

proc pumpWayembedHost*(host: var WayembedHost) =
  if not host.server.isNil:
    wayembedServerDispatch(host.server)
    wayembedServerFlush(host.server)

proc shutdownWayembedHost*(host: var WayembedHost) =
  if not host.server.isNil:
    wayembedServerDestroy(host.server)
  host = WayembedHost()

proc attachWayembedChild*(
    host: var WayembedHost,
    client: ptr WayembedClient,
    parentSurface: pointer,
    childSurface: pointer,
): uint32 =
  var info = WayembedAttachInfo(
    size: uint32(sizeof(WayembedAttachInfo)),
    version: WayembedAbiVersion,
    client: client,
    parentSurface: cast[ptr WlSurface](parentSurface),
    childSurface: cast[ptr WlSurface](childSurface),
  )
  result = wayembedEmbedAttach(addr info, addr host.embed)
  host.failed = result != WayembedEmbedStatusOk

proc adoptWayembedSubsurface*(
    host: var WayembedHost,
    client: ptr WayembedClient,
    parentSurface: pointer,
    childSurface: pointer,
): uint32 =
  var info = WayembedAttachInfo(
    size: uint32(sizeof(WayembedAttachInfo)),
    version: WayembedAbiVersion,
    client: client,
    parentSurface: cast[ptr WlSurface](parentSurface),
    childSurface: cast[ptr WlSurface](childSurface),
  )
  result = wayembedEmbedAdoptSubsurface(addr info, addr host.embed)
  host.failed = result != WayembedEmbedStatusOk

proc resizeWayembedHost*(host: var WayembedHost, width, height: int32): bool =
  if host.embed.isNil or width <= 0 or height <= 0:
    return false
  let status = wayembedEmbedResize(host.embed, width, height)
  result = status == WayembedEmbedStatusOk
  if result:
    host.width = width
    host.height = height
  else:
    host.failed = true
