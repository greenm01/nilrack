import std/[dynlib, os, strformat]
import ../platform/wayland_app

const
  DefaultNilampBundle* = "/home/niltempus/dev/nilamp/native/bin/nilamp-twd-mkii.vst3"
  DefaultVst3UiShim* = "build/libnilrack_vst3_ui_shim.so"
  DefaultEditorWidth* = 750'i32
  DefaultEditorHeight* = 510'i32

type
  NilrackWaylandHandles {.bycopy.} = object
    size*: uint32
    display*: pointer
    compositor*: pointer
    subcompositor*: pointer
    shm*: pointer
    seat*: pointer
    xdgWmBase*: pointer
    parentSurface*: pointer

  CreateFn = proc(
    bundlePath: cstring,
    handles: ptr NilrackWaylandHandles,
    width: int32,
    height: int32,
    outUi: ptr pointer,
  ): int32 {.cdecl.}
  PumpFn = proc(ui: pointer): int32 {.cdecl.}
  ResizeFn = proc(ui: pointer, width: int32, height: int32): int32 {.cdecl.}
  DestroyFn = proc(ui: pointer) {.cdecl.}

  Vst3UiHost* = object
    lib: LibHandle
    ui: pointer
    pumpFn: PumpFn
    resizeFn: ResizeFn
    destroyFn: DestroyFn

proc sym[T](lib: LibHandle, name: string): T =
  let address = lib.symAddr(name)
  if address == nil:
    raise newException(ValueError, "missing VST3 UI shim symbol: " & name)
  cast[T](address)

proc initNilampVst3Ui*(
    host: var Vst3UiHost,
    app: WaylandApp,
    bundlePath = getEnv("NILRACK_NILAMP_VST3", DefaultNilampBundle),
    shimPath = getEnv("NILRACK_VST3_UI_SHIM", DefaultVst3UiShim),
): bool =
  if not fileExists(shimPath):
    stderr.writeLine &"nilrack: VST3 UI shim not found: {shimPath}"
    return false
  if not dirExists(bundlePath):
    stderr.writeLine &"nilrack: nilamp VST3 bundle not found: {bundlePath}"
    return false
  if app.subcompositor == nil:
    stderr.writeLine "nilrack: wl_subcompositor is required for VST3 Wayland UI"
    return false

  host.lib = loadLib(shimPath)
  if host.lib == nil:
    stderr.writeLine &"nilrack: failed to load VST3 UI shim: {shimPath}"
    return false

  let createFn = sym[CreateFn](host.lib, "nilrack_vst3_ui_create")
  host.pumpFn = sym[PumpFn](host.lib, "nilrack_vst3_ui_pump")
  host.resizeFn = sym[ResizeFn](host.lib, "nilrack_vst3_ui_resize")
  host.destroyFn = sym[DestroyFn](host.lib, "nilrack_vst3_ui_destroy")

  var handles = NilrackWaylandHandles(
    size: uint32(sizeof(NilrackWaylandHandles)),
    display: cast[pointer](app.display),
    compositor: cast[pointer](app.compositor),
    subcompositor: cast[pointer](app.subcompositor),
    shm: cast[pointer](app.wlShm),
    seat: cast[pointer](app.seat),
    xdgWmBase: cast[pointer](app.xdgWmBase),
    parentSurface: cast[pointer](app.surface),
  )

  var ui: pointer
  let status = createFn(
    bundlePath.cstring, handles.addr, DefaultEditorWidth, DefaultEditorHeight, ui.addr
  )
  if status != 0 or ui == nil:
    stderr.writeLine &"nilrack: nilamp VST3 UI create failed: status={status}"
    unloadLib(host.lib)
    host = Vst3UiHost()
    return false

  host.ui = ui
  true

proc pumpNilampVst3Ui*(host: var Vst3UiHost) =
  if host.ui != nil and host.pumpFn != nil:
    discard host.pumpFn(host.ui)

proc resizeNilampVst3Ui*(host: var Vst3UiHost, width, height: int32) =
  if host.ui != nil and host.resizeFn != nil and width > 0 and height > 0:
    discard host.resizeFn(host.ui, min(width, DefaultEditorWidth), DefaultEditorHeight)

proc shutdownNilampVst3Ui*(host: var Vst3UiHost) =
  if host.ui != nil and host.destroyFn != nil:
    host.destroyFn(host.ui)
  if host.lib != nil:
    unloadLib(host.lib)
  host = Vst3UiHost()
