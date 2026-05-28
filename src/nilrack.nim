import std/[atomics, options, os]
import state/engine
import platform/wayland_app
import render/renderer
import audio/backend_reconfiguration
import audio/jack_backend
import audio/param_event_queue
import audio/process_callback
import systems/effect_queue
import systems/plugin_scan
import systems/render_projection
import systems/graph_process_plan
import systems/update
import plugins/[clap_host, plugin_adapter]
import plugins/vst3_host

type AppArgs = object
  clapPath: string
  scanPluginPath: string
  vst3UiSpike: bool

proc printUsage() =
  stderr.writeLine(
    "usage: nilrack [--clap <path>] [--vst3-ui-spike] [--scan-plugin <path>]"
  )

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
    of "--scan-plugin":
      inc i
      if i > paramCount():
        printUsage()
        quit(1)
      result.scanPluginPath = paramStr(i)
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
  if result.scanPluginPath.len > 0 and (result.clapPath.len > 0 or result.vst3UiSpike):
    stderr.writeLine("nilrack: --scan-plugin cannot be combined with live host modes")
    quit(1)

proc runScanPlugin(path: string) =
  let clap = loadClapPlugin(path)
  if not clap.ok:
    stderr.writeLine("nilrack: " & clap.error)
    quit(1)
  stdout.write(clap.descriptor.scanDescriptorToKdl(pluginMtime(path)))
  clap.plugin.close()
  quit(0)

proc publishSingleClapProcessPlan(
    jack: var JackBackend,
    model: NilrackModel,
    activeAttach: PluginAttachResult,
    activeDescriptor: PluginDescriptor,
    activeClap: ClapLoadedPlugin,
    processPlan: var ProcessPlan,
): bool =
  if activeClap.isNil:
    return false
  processPlan = buildSingleClapProcessPlan(
    activeAttach.nodeId, activeAttach.pluginId, activeDescriptor, activeClap
  )
  let node = model.nodeData(activeAttach.nodeId)
  if node.isSome:
    processPlan.applyHostNodeState(node.get)
  discard jack.publishJackProcessPlan(addr processPlan)
  true

when isMainModule:
  let args = parseArgs()
  if args.scanPluginPath.len > 0:
    runScanPlugin(args.scanPluginPath)

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
    discard jack.publishSingleClapProcessPlan(
      model, activeAttach, activeDescriptor, activeClap, processPlan
    )

  activateJack(jack)

  var nilampUi: Vst3UiHost
  if args.vst3UiSpike:
    discard nilampUi.initNilampVst3Ui(app)

  var frame: NilDrawList
  var committedActions: ActionLog
  var effects: EffectQueue
  var updateCommands: UpdateCommandQueue

  while app.running:
    discard app.pollAndDispatch()
    if args.vst3UiSpike:
      nilampUi.pumpNilampVst3Ui()
    let msgs = app.drainMsgs()
    for msg in msgs:
      model.dispatchMsg(committedActions, effects, updateCommands, msg)
    var command: UpdateCommand
    while updateCommands.popUpdateCommand(command):
      case command.kind
      of uckResize:
        r.resizeRenderer(command.width.uint32, command.height.uint32)
        if args.vst3UiSpike:
          nilampUi.resizeNilampVst3Ui(command.width, command.height)
      of uckClose:
        app.running = false
      of uckEnqueueParamValue:
        discard jack.enqueuePluginParamValue(
          command.pluginId, command.paramId, command.normalizedValue
        )
      of uckPublishProcessPlan:
        discard jack.publishSingleClapProcessPlan(
          model, activeAttach, activeDescriptor, activeClap, processPlan
        )
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
          discard jack.publishSingleClapProcessPlan(
            model, activeAttach, activeDescriptor, activeClap, processPlan
          )
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
