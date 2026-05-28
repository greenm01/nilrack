import std/[atomics, os]
import state/engine
import platform/wayland_app
import render/renderer
import audio/backend_reconfiguration
import audio/jack_backend
import audio/param_event_queue
import audio/process_callback
import audio/process_plan_store
import systems/effect_queue
import systems/graph_compile
import systems/plugin_browser
import systems/plugin_scan
import systems/render_projection
import systems/graph_process_plan
import systems/plugin_lifecycle
import systems/update
import plugins/[clap_host, plugin_adapter]
import plugins/vst3_host

type AppArgs = object
  clapPath: string
  scanPluginPath: string
  scanCachePath: string
  pluginFilter: string
  vst3UiSpike: bool

proc printUsage() =
  stderr.writeLine(
    "usage: nilrack [--clap <path>] [--vst3-ui-spike] " &
      "[--scan-cache <path>] [--plugin-filter <text>] [--scan-plugin <path>]"
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
    of "--scan-cache":
      inc i
      if i > paramCount():
        printUsage()
        quit(1)
      result.scanCachePath = paramStr(i)
    of "--plugin-filter":
      inc i
      if i > paramCount():
        printUsage()
        quit(1)
      result.pluginFilter = paramStr(i)
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
  if result.scanPluginPath.len > 0 and (
    result.clapPath.len > 0 or result.vst3UiSpike or result.scanCachePath.len > 0 or
    result.pluginFilter.len > 0
  ):
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
    retireQueue: var ProcessPlanRetireQueue,
    model: NilrackModel,
    rackId: RackId,
    runtimes: PluginRuntimeStore,
): bool =
  if rackId == NullRackId:
    return false
  let report = model.compileRackGraph(rackId, runtimes)
  if report.hasCompileErrors:
    return false
  let plan = model.buildProcessPlanFromCompiledGraph(report.plan, runtimes)
  let published = cast[ptr ProcessPlan](alloc0(sizeof(ProcessPlan)))
  published[] = plan
  let retired = jack.publishJackProcessPlan(published)
  if not retireQueue.enqueueRetiredProcessPlan(jack.planSlot, retired):
    discard
  true

proc drainRetiredProcessPlans(
    retireQueue: var ProcessPlanRetireQueue, slot: var ProcessPlanSlot
) =
  var retired = retireQueue.popReadyRetiredProcessPlan(slot)
  while not retired.isNil:
    dealloc(retired)
    retired = retireQueue.popReadyRetiredProcessPlan(slot)

proc drainRetiredProcessPlansImmediate(retireQueue: var ProcessPlanRetireQueue) =
  var retired = retireQueue.popRetiredProcessPlanImmediate()
  while not retired.isNil:
    dealloc(retired)
    retired = retireQueue.popRetiredProcessPlanImmediate()

when isMainModule:
  let args = parseArgs()
  if args.scanPluginPath.len > 0:
    runScanPlugin(args.scanPluginPath)

  var activeClap: ClapLoadedPlugin
  var activeAttach: PluginAttachResult
  var runtimeStore: PluginRuntimeStore
  var model = NilrackModel()
  let defaultRackId = model.firstRackIdOrCreateDefault()
  discard model.ensureRackAudioIoNodes(defaultRackId)
  model.pluginBrowser = loadPluginBrowserEntries(args.scanCachePath)
  model.pluginBrowser.nameFilter = args.pluginFilter
  if args.clapPath.len > 0:
    let clap = loadClapPlugin(args.clapPath)
    if not clap.ok:
      stderr.writeLine("nilrack: " & clap.error)
      quit(1)
    activeClap = clap.plugin
    activeAttach = model.attachPluginDescriptor(clap.descriptor)
    activeClap.bindClapPluginId(activeAttach.pluginId)
    discard runtimeStore.addPluginRuntime(
      activeClap.clapPluginRuntimeRef(activeAttach.pluginId)
    )

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

  var retiredPlans: ProcessPlanRetireQueue
  retiredPlans.initProcessPlanRetireQueue()
  var lastBackendReconfigGeneration: uint32
  if not activeClap.isNil:
    if not activeClap.activateClap(jack.sampleRate.float64, 1, jack.bufferSize):
      stderr.writeLine("nilrack: failed to activate CLAP plugin")
      quit(1)
    if not activeClap.startClapProcessing():
      stderr.writeLine("nilrack: failed to start CLAP processing")
      quit(1)
    discard jack.publishSingleClapProcessPlan(
      retiredPlans, model, activeAttach.rackId, runtimeStore
    )

  activateJack(jack)

  var nilampUi: Vst3UiHost
  if args.vst3UiSpike:
    discard nilampUi.initNilampVst3Ui(app)

  var frame: NilDrawList
  var inputTargets: InputTargetList
  var committedActions: ActionLog
  var effects: EffectQueue
  var updateCommands: UpdateCommandQueue
  frame.project(inputTargets, model, app.width.float32, app.height.float32, 0.0, 0.0)

  while app.running:
    discard app.pollAndDispatch()
    if args.vst3UiSpike:
      nilampUi.pumpNilampVst3Ui()
    let msgs = app.drainMsgs()
    for msg in msgs:
      model.dispatchMsg(committedActions, effects, updateCommands, inputTargets, msg)
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
          retiredPlans, model, activeAttach.rackId, runtimeStore
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
      discard retiredPlans.enqueueRetiredProcessPlan(jack.planSlot, retiredPlan)
      if not activeClap.isNil:
        activeClap.stopClapProcessing()
        activeClap.deactivateClap()
        if activeClap.activateClap(jack.sampleRate.float64, 1, jack.bufferSize) and
            activeClap.startClapProcessing():
          discard jack.publishSingleClapProcessPlan(
            retiredPlans, model, activeAttach.rackId, runtimeStore
          )
        else:
          stderr.writeLine(
            "nilrack: failed to reactivate CLAP plugin after JACK change"
          )
    let mIn = meterLevels[0].load(moRelaxed)
    let mOut = meterLevels[1].load(moRelaxed)
    retiredPlans.drainRetiredProcessPlans(jack.planSlot)
    frame.project(inputTargets, model, app.width.float32, app.height.float32, mIn, mOut)
    r.renderFrame(frame)

  deactivateJack(jack)
  discard retiredPlans.enqueueRetiredProcessPlan(
    jack.planSlot, jack.publishJackProcessPlan(nil)
  )
  retiredPlans.drainRetiredProcessPlansImmediate()
  shutdownJackBackend(jack)
  if not activeClap.isNil:
    activeClap.stopClapProcessing()
    activeClap.deactivateClap()
  if args.vst3UiSpike:
    nilampUi.shutdownNilampVst3Ui()
  activeClap.close()
  r.shutdownRenderer()
  shutdownWaylandApp(app)
