import std/[atomics, options, os]
import state/engine
import platform/wayland_app
import render/renderer
import audio/backend_reconfiguration
import audio/jack_backend
import audio/process_callback
import systems/action_log
import systems/effect_queue
import systems/render_projection
import systems/graph_process_plan
import systems/ui_hit_test
import plugins/[clap_host, plugin_adapter]
import plugins/vst3_host

type AppArgs = object
  clapPath: string
  vst3UiSpike: bool

proc printUsage() =
  stderr.writeLine("usage: nilrack [--clap <path>] [--vst3-ui-spike]")

proc parseArgs(): AppArgs =
  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    case arg
    of "--clap":
      inc i
      if i > paramCount():
        printUsage()
        quit(1)
      result.clapPath = paramStr(i)
    of "--vst3-ui-spike":
      result.vst3UiSpike = true
    of "--help", "-h":
      printUsage()
      quit(0)
    else:
      stderr.writeLine("nilrack: unknown argument: " & arg)
      printUsage()
      quit(1)
    inc i

  if result.clapPath.len > 0 and result.vst3UiSpike:
    stderr.writeLine("nilrack: --clap and --vst3-ui-spike are separate smoke paths")
    quit(1)

when isMainModule:
  let args = parseArgs()

  var activeClap: ClapLoadedPlugin
  var activeDescriptor: PluginDescriptor
  var activeAttach: PluginAttachResult
  var model = NilrackModel()
  if args.clapPath.len > 0:
    let clap = loadClapPlugin(args.clapPath)
    if not clap.ok:
      stderr.writeLine("nilrack: " & clap.error)
      quit(1)
    activeClap = clap.plugin
    activeDescriptor = clap.descriptor
    activeAttach = model.attachPluginDescriptor(activeDescriptor)
    activeClap.bindClapPluginId(activeAttach.pluginId)

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

  var processPlan: ProcessPlan
  var lastBackendReconfigGeneration: uint32
  if not activeClap.isNil:
    if not activeClap.activateClap(jack.sampleRate.float64, 1, jack.bufferSize):
      stderr.writeLine("nilrack: failed to activate CLAP plugin")
      quit(1)
    if not activeClap.startClapProcessing():
      stderr.writeLine("nilrack: failed to start CLAP processing")
      quit(1)
    processPlan = buildSingleClapProcessPlan(
      activeAttach.nodeId, activeAttach.pluginId, activeDescriptor, activeClap
    )
    discard jack.publishJackProcessPlan(addr processPlan)

  activateJack(jack)

  var nilampUi: Vst3UiHost
  if args.vst3UiSpike:
    discard nilampUi.initNilampVst3Ui(app)

  var frame: NilDrawList
  var committedActions: ActionLog
  var effects: EffectQueue

  while app.running:
    discard app.pollAndDispatch()
    if args.vst3UiSpike:
      nilampUi.pumpNilampVst3Ui()
    let msgs = app.drainMsgs()
    for msg in msgs:
      discard committedActions.recordCommittedAction(msg)
      discard effects.routeMsgEffects(msg)
      case msg.kind
      of msgResize:
        r.resizeRenderer(msg.resizeW.uint32, msg.resizeH.uint32)
        if args.vst3UiSpike:
          nilampUi.resizeNilampVst3Ui(msg.resizeW, msg.resizeH)
      of msgKeyPress:
        if msg.keyCode == 1:
          app.running = false
      of msgPointerButton:
        if msg.btnPressed:
          let bypassNode = model.bypassToggleAt(msg.btnX, msg.btnY)
          if bypassNode.isSome:
            model.nodeToggleBypass(bypassNode.get)
      else:
        discard
    var effect: Effect
    while effects.popEffect(effect):
      case effect.kind
      of ekGraphDirty, ekProcessPlanDirty, ekTopologyRefresh, ekDiagnosticsDirty,
          ekStateDirty:
        discard
    var retiredPlan: ptr ProcessPlan
    if jack.consumeAudioReconfigurationRequest(
      lastBackendReconfigGeneration, retiredPlan
    ):
      # The smoke path reuses stack-owned plan storage; heap plans enqueue retiredPlan.
      discard retiredPlan
      if not activeClap.isNil:
        activeClap.stopClapProcessing()
        activeClap.deactivateClap()
        if activeClap.activateClap(jack.sampleRate.float64, 1, jack.bufferSize) and
            activeClap.startClapProcessing():
          processPlan = buildSingleClapProcessPlan(
            activeAttach.nodeId, activeAttach.pluginId, activeDescriptor, activeClap
          )
          discard jack.publishJackProcessPlan(addr processPlan)
        else:
          stderr.writeLine(
            "nilrack: failed to reactivate CLAP plugin after JACK change"
          )
    let mIn = meterLevels[0].load(moRelaxed)
    let mOut = meterLevels[1].load(moRelaxed)
    frame.project(model, app.width.float32, app.height.float32, mIn, mOut)
    r.renderFrame(frame)

  deactivateJack(jack)
  shutdownJackBackend(jack)
  if not activeClap.isNil:
    activeClap.stopClapProcessing()
    activeClap.deactivateClap()
  if args.vst3UiSpike:
    nilampUi.shutdownNilampVst3Ui()
  activeClap.close()
  r.shutdownRenderer()
  shutdownWaylandApp(app)
