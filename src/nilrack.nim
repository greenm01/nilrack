import std/atomics
import state/engine
import platform/wayland_app
import render/renderer
import audio/jack_backend
import audio/process_callback
import systems/render_projection
import plugins/vst3_host

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

  var jack: JackBackend
  initJackBackend(jack, "nilrack")
  activateJack(jack)

  var nilampUi: Vst3UiHost
  discard nilampUi.initNilampVst3Ui(app)

  var model = NilrackModel()
  var frame: NilDrawList

  while app.running:
    discard app.pollAndDispatch()
    nilampUi.pumpNilampVst3Ui()
    let msgs = app.drainMsgs()
    for msg in msgs:
      case msg.kind
      of msgResize:
        r.resizeRenderer(msg.resizeW.uint32, msg.resizeH.uint32)
        nilampUi.resizeNilampVst3Ui(msg.resizeW, msg.resizeH)
      of msgKeyPress:
        if msg.keyCode == 1:
          app.running = false
      else:
        discard
    let mIn = meterLevels[0].load(moRelaxed)
    let mOut = meterLevels[1].load(moRelaxed)
    frame.project(model, app.width.float32, app.height.float32, mIn, mOut)
    r.renderFrame(frame)

  deactivateJack(jack)
  shutdownJackBackend(jack)
  nilampUi.shutdownNilampVst3Ui()
  r.shutdownRenderer()
  shutdownWaylandApp(app)
