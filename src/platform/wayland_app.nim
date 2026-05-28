import std/posix
import wayland/native/client
import wayland/native/common
import wayland/protocols/wayland/client as wlCore
import wayland/protocols/stable/xdgshell/client as xdgShell
import ../types/ui_values

proc getpid(): cint {.importc: "getpid", header: "<unistd.h>".}

const
  DefaultWidth* = 1280'i32
  DefaultHeight* = 720'i32

type WaylandApp* = object
  display*: ptr Display
  registry*: ptr Registry
  compositor*: ptr Compositor
  subcompositor*: ptr Subcompositor
  wlShm*: ptr Shm
  xdgWmBase*: ptr XdgWmBase
  seat*: ptr Seat
  surface*: ptr Surface
  xdgSurface*: ptr XdgSurface
  xdgToplevel*: ptr XdgToplevel
  wlPointer*: ptr Pointer
  wlKeyboard*: ptr Keyboard
  fallbackBuffer*: ptr Buffer
  width*: int32
  height*: int32
  configured*: bool
  running*: bool
  pendingMsgs*: seq[Msg]
  pointerX*, pointerY*: float32

func fixedToFloat(f: Fixed): float32 =
  float32(int32(f)) / 256.0

# Forward-declare all listener vars so callbacks can reference them.
var registryListener: RegistryListener
var xdgWmBaseListener: XdgWmBaseListener
var xdgSurfaceListener: XdgSurfaceListener
var xdgToplevelListener: XdgToplevelListener
var seatListener: SeatListener
var pointerListener: PointerListener
var keyboardListener: KeyboardListener

# ---  Callbacks  --------------------------------------------------------------

proc onRegistryGlobal(
    data: pointer,
    registry: ptr Registry,
    name: uint32,
    interfaceName: cstring,
    version: uint32,
) =
  let app = cast[ptr WaylandApp](data)
  let iface = $interfaceName
  if iface == "wl_compositor":
    app.compositor = cast[ptr Compositor](registry.`bind`(
      name, wl_compositor_interface.addr, min(version, 4'u32)
    ))
  elif iface == "wl_subcompositor":
    app.subcompositor = cast[ptr Subcompositor](registry.`bind`(
      name, wl_subcompositor_interface.addr, min(version, 1'u32)
    ))
  elif iface == "xdg_wm_base":
    app.xdgWmBase = cast[ptr XdgWmBase](registry.`bind`(
      name, xdg_wm_base_interface.addr, min(version, 3'u32)
    ))
    discard app.xdgWmBase.addListener(xdgWmBaseListener.addr, data)
  elif iface == "wl_shm":
    app.wlShm =
      cast[ptr Shm](registry.`bind`(name, wl_shm_interface.addr, min(version, 1'u32)))
  elif iface == "wl_seat":
    app.seat =
      cast[ptr Seat](registry.`bind`(name, wl_seat_interface.addr, min(version, 5'u32)))
    discard app.seat.addListener(seatListener.addr, data)

proc onRegistryGlobalRemove(data: pointer, registry: ptr Registry, name: uint32) =
  discard

proc onXdgWmBasePing(data: pointer, xdgWmBase: ptr XdgWmBase, serial: uint32) =
  xdgWmBase.pong(serial)

proc onXdgSurfaceConfigure(data: pointer, xdgSurface: ptr XdgSurface, serial: uint32) =
  let app = cast[ptr WaylandApp](data)
  xdgSurface.ackConfigure(serial)
  app.surface.commit()
  app.configured = true

proc onXdgToplevelConfigure(
    data: pointer,
    xdgToplevel: ptr XdgToplevel,
    width: int32,
    height: int32,
    states: ptr Array,
) =
  let app = cast[ptr WaylandApp](data)
  let w = if width > 0: width else: DefaultWidth
  let h = if height > 0: height else: DefaultHeight
  if w != app.width or h != app.height:
    app.width = w
    app.height = h
    if app.configured:
      app.pendingMsgs.add(Msg(kind: msgResize, resizeW: w, resizeH: h))

proc onXdgToplevelClose(data: pointer, xdgToplevel: ptr XdgToplevel) =
  cast[ptr WaylandApp](data).running = false

proc onXdgToplevelConfigureBounds(
    data: pointer, xdgToplevel: ptr XdgToplevel, width: int32, height: int32
) =
  discard

proc onXdgToplevelWmCapabilities(
    data: pointer, xdgToplevel: ptr XdgToplevel, capabilities: ptr Array
) =
  discard

proc onSeatCapabilities(data: pointer, seat: ptr Seat, caps: uint32) =
  let app = cast[ptr WaylandApp](data)
  if (caps and uint32(capability_pointer)) != 0:
    if app.wlPointer == nil:
      app.wlPointer = seat.getPointer()
      discard app.wlPointer.addListener(pointerListener.addr, data)
  elif app.wlPointer != nil:
    app.wlPointer.release()
    app.wlPointer = nil
  if (caps and uint32(capability_keyboard)) != 0:
    if app.wlKeyboard == nil:
      app.wlKeyboard = seat.getKeyboard()
      discard app.wlKeyboard.addListener(keyboardListener.addr, data)
  elif app.wlKeyboard != nil:
    app.wlKeyboard.release()
    app.wlKeyboard = nil

proc onSeatName(data: pointer, seat: ptr Seat, name: cstring) =
  discard

proc onPointerEnter(
    data: pointer,
    pointer: ptr Pointer,
    serial: uint32,
    surface: ptr Surface,
    sx: Fixed,
    sy: Fixed,
) =
  let app = cast[ptr WaylandApp](data)
  app.pointerX = fixedToFloat(sx)
  app.pointerY = fixedToFloat(sy)

proc onPointerLeave(
    data: pointer, pointer: ptr Pointer, serial: uint32, surface: ptr Surface
) =
  discard

proc onPointerMotion(
    data: pointer, pointer: ptr Pointer, time: uint32, sx: Fixed, sy: Fixed
) =
  let app = cast[ptr WaylandApp](data)
  app.pointerX = fixedToFloat(sx)
  app.pointerY = fixedToFloat(sy)
  app.pendingMsgs.add(
    Msg(kind: msgPointerMotion, motionX: app.pointerX, motionY: app.pointerY)
  )

proc onPointerButton(
    data: pointer,
    pointer: ptr Pointer,
    serial: uint32,
    time: uint32,
    button: uint32,
    state: uint32,
) =
  let app = cast[ptr WaylandApp](data)
  app.pendingMsgs.add(
    Msg(
      kind: msgPointerButton,
      btnButton: button,
      btnPressed: state != 0,
      btnX: app.pointerX,
      btnY: app.pointerY,
    )
  )

proc onPointerAxis(
    data: pointer, pointer: ptr Pointer, time: uint32, axis: uint32, value: Fixed
) =
  let app = cast[ptr WaylandApp](data)
  app.pendingMsgs.add(
    Msg(kind: msgPointerScroll, scrollAxis: axis, scrollValue: fixedToFloat(value))
  )

proc onPointerFrame(data: pointer, pointer: ptr Pointer) =
  discard

proc onPointerAxisSource(data: pointer, pointer: ptr Pointer, axisSource: uint32) =
  discard

proc onPointerAxisStop(
    data: pointer, pointer: ptr Pointer, time: uint32, axis: uint32
) =
  discard

proc onPointerAxisDiscrete(
    data: pointer, pointer: ptr Pointer, axis: uint32, discrete: int32
) =
  discard

proc onPointerAxisValue120(
    data: pointer, pointer: ptr Pointer, axis: uint32, value120: int32
) =
  discard

proc onPointerAxisRelativeDirection(
    data: pointer, pointer: ptr Pointer, axis: uint32, direction: uint32
) =
  discard

proc onKeyboardKeymap(
    data: pointer, keyboard: ptr Keyboard, format: uint32, fd: int32, size: uint32
) =
  discard posix.close(fd)

proc onKeyboardEnter(
    data: pointer,
    keyboard: ptr Keyboard,
    serial: uint32,
    surface: ptr Surface,
    keys: ptr Array,
) =
  discard

proc onKeyboardLeave(
    data: pointer, keyboard: ptr Keyboard, serial: uint32, surface: ptr Surface
) =
  discard

proc onKeyboardKey(
    data: pointer,
    keyboard: ptr Keyboard,
    serial: uint32,
    time: uint32,
    key: uint32,
    state: uint32,
) =
  let app = cast[ptr WaylandApp](data)
  if state != 0:
    app.pendingMsgs.add(Msg(kind: msgKeyPress, keyCode: key))
  else:
    app.pendingMsgs.add(Msg(kind: msgKeyRelease, keyCode: key))

proc onKeyboardModifiers(
    data: pointer,
    keyboard: ptr Keyboard,
    serial: uint32,
    modsDepressed: uint32,
    modsLatched: uint32,
    modsLocked: uint32,
    group: uint32,
) =
  discard

proc onKeyboardRepeatInfo(
    data: pointer, keyboard: ptr Keyboard, rate: int32, delay: int32
) =
  discard

# Assign listener values after all callbacks are defined.
registryListener =
  RegistryListener(global: onRegistryGlobal, globalRemove: onRegistryGlobalRemove)
xdgWmBaseListener = XdgWmBaseListener(ping: onXdgWmBasePing)
xdgSurfaceListener = XdgSurfaceListener(configure: onXdgSurfaceConfigure)
xdgToplevelListener = XdgToplevelListener(
  configure: onXdgToplevelConfigure,
  close: onXdgToplevelClose,
  configureBounds: onXdgToplevelConfigureBounds,
  wmCapabilities: onXdgToplevelWmCapabilities,
)
seatListener = SeatListener(capabilities: onSeatCapabilities, name: onSeatName)
pointerListener = PointerListener(
  enter: onPointerEnter,
  leave: onPointerLeave,
  motion: onPointerMotion,
  button: onPointerButton,
  axis: onPointerAxis,
  frame: onPointerFrame,
  axisSource: onPointerAxisSource,
  axisStop: onPointerAxisStop,
  axisDiscrete: onPointerAxisDiscrete,
  axisValue120: onPointerAxisValue120,
  axisRelativeDirection: onPointerAxisRelativeDirection,
)
keyboardListener = KeyboardListener(
  keymap: onKeyboardKeymap,
  enter: onKeyboardEnter,
  leave: onKeyboardLeave,
  key: onKeyboardKey,
  modifiers: onKeyboardModifiers,
  repeatInfo: onKeyboardRepeatInfo,
)

# ---  SHM fallback buffer  ----------------------------------------------------

proc attachFallbackBuffer*(app: var WaylandApp) =
  if app.wlShm == nil or app.surface == nil:
    return
  if app.width <= 0 or app.height <= 0:
    return
  let stride = app.width * 4
  let size = stride * app.height
  let path = "/tmp/nilrack-shm-" & $getpid()
  let fd = posix.open(path.cstring, O_CREAT or O_RDWR or O_TRUNC, Mode(0o600))
  if fd < 0:
    return
  discard posix.unlink(path.cstring)
  if ftruncate(fd, Off(size)) < 0:
    discard posix.close(fd)
    return
  let data = mmap(nil, size.int, PROT_READ or PROT_WRITE, MAP_SHARED, fd, Off(0))
  if data != MAP_FAILED:
    let pixels = cast[ptr UncheckedArray[uint32]](data)
    for i in 0 ..< (size div 4):
      pixels[i] = 0xFF1A1A1A'u32 # opaque dark background
    discard munmap(data, size.int)
  let pool = app.wlShm.createPool(fd, size.int32)
  discard posix.close(fd)
  if pool == nil:
    return
  if app.fallbackBuffer != nil:
    app.fallbackBuffer.destroy()
  app.fallbackBuffer =
    pool.createBuffer(0, app.width, app.height, stride, uint32(format_argb8888))
  pool.destroy()
  if app.fallbackBuffer == nil:
    return
  app.surface.attach(app.fallbackBuffer, 0, 0)
  app.surface.commit()

# ---  Public API  -------------------------------------------------------------

proc initWaylandApp*(app: var WaylandApp, title: string = "nilrack") =
  app.width = DefaultWidth
  app.height = DefaultHeight

  app.display = connect_display(nil)
  doAssert app.display != nil, "failed to connect to Wayland display"

  app.registry = app.display.getRegistry()
  doAssert app.registry != nil, "failed to get Wayland registry"

  discard app.registry.addListener(registryListener.addr, addr app)
  discard app.display.roundtrip()

  doAssert app.compositor != nil, "compositor not advertised"
  doAssert app.xdgWmBase != nil, "xdg_wm_base not advertised"

  app.surface = app.compositor.createSurface()
  doAssert app.surface != nil, "failed to create wl_surface"

  app.xdgSurface = app.xdgWmBase.getXdgSurface(app.surface)
  doAssert app.xdgSurface != nil, "failed to create xdg_surface"
  discard app.xdgSurface.addListener(xdgSurfaceListener.addr, addr app)

  app.xdgToplevel = app.xdgSurface.getToplevel()
  doAssert app.xdgToplevel != nil, "failed to create xdg_toplevel"
  discard app.xdgToplevel.addListener(xdgToplevelListener.addr, addr app)

  app.xdgToplevel.setTitle(title.cstring)
  app.xdgToplevel.setAppId("nilrack".cstring)

  app.surface.commit()
  while not app.configured:
    discard app.display.dispatch()

  app.running = true

proc pollAndDispatch*(app: var WaylandApp): bool =
  if app.display.dispatch_pending() < 0:
    return false
  discard app.display.flush()

  var fd = TPollfd(fd: app.display.get_fd(), events: POLLIN, revents: 0)
  let ready = poll(addr fd, Tnfds(1), 16)
  if ready > 0:
    if app.display.dispatch() < 0:
      return false
  true

proc drainMsgs*(app: var WaylandApp): seq[Msg] =
  result = move(app.pendingMsgs)
  app.pendingMsgs = @[]

proc shutdownWaylandApp*(app: var WaylandApp) =
  if app.fallbackBuffer != nil:
    app.fallbackBuffer.destroy()
  if app.wlPointer != nil:
    app.wlPointer.release()
  if app.wlKeyboard != nil:
    app.wlKeyboard.release()
  if app.xdgToplevel != nil:
    app.xdgToplevel.destroy()
  if app.xdgSurface != nil:
    app.xdgSurface.destroy()
  if app.surface != nil:
    app.surface.destroy()
  if app.xdgWmBase != nil:
    app.xdgWmBase.destroy()
  if app.seat != nil:
    app.seat.release()
  if app.subcompositor != nil:
    app.subcompositor.destroy()
  if app.compositor != nil:
    app.compositor.destroy()
  if app.registry != nil:
    app.registry.destroy()
  if app.display != nil:
    app.display.disconnect()
