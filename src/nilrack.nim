import state/engine
import platform/wayland_app
import render/renderer
import render/draw_list

when isMainModule:
  var app: WaylandApp
  initWaylandApp(app)

  var r: Renderer
  initRenderer(
    r,
    cast[pointer](app.display),
    cast[pointer](app.surface),
    app.width.uint32,
    app.height.uint32,
  )

  var model = NilrackModel()
  var frame: NilDrawList

  while app.running:
    discard app.pollAndDispatch()
    let msgs = app.drainMsgs()
    for msg in msgs:
      case msg.kind
      of msgResize:
        r.resizeRenderer(msg.resizeW.uint32, msg.resizeH.uint32)
      of msgKeyPress:
        if msg.keyCode == 1:
          app.running = false
      else:
        discard
    frame.clear()
    r.renderFrame(frame)

  r.shutdownRenderer()
  shutdownWaylandApp(app)
