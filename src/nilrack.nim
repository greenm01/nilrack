import state/engine
import platform/wayland_app

when isMainModule:
  var app: WaylandApp
  initWaylandApp(app)

  var model = NilrackModel()

  while app.running:
    discard app.pollAndDispatch()
    let msgs = app.drainMsgs()
    for msg in msgs:
      case msg.kind
      of msgKeyPress:
        if msg.keyCode == 1: # Escape (Linux evdev scancode)
          app.running = false
      else:
        discard

  shutdownWaylandApp(app)
