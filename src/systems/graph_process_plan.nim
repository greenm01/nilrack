import std/options

import ../plugins/clap_host
import ../state/[model, queries]
import ../types/[audio_values, core, plugin_values]
import ../types/plugin_runtime_values

proc addPlanNode*(plan: var ProcessPlan, nodeId: NodeId): bool =
  if plan.nodeCount >= MaxProcessPlanNodes.uint32:
    plan.capacityExceeded = true
    return false
  plan.nodes[plan.nodeCount.int] = nodeId
  inc plan.nodeCount
  true

proc hasPluginTarget(plan: ProcessPlan, pluginId: PluginId): bool =
  for i in 0 ..< plan.pluginTargetCount.int:
    if plan.pluginTargets[i] == pluginId:
      return true
  false

proc addPluginTarget*(plan: var ProcessPlan, pluginId: PluginId): bool =
  if pluginId == NullPluginId:
    return false
  if plan.hasPluginTarget(pluginId):
    return true
  if plan.pluginTargetCount >= MaxProcessPlanPluginTargets.uint32:
    plan.capacityExceeded = true
    return false
  plan.pluginTargets[plan.pluginTargetCount.int] = pluginId
  inc plan.pluginTargetCount
  true

proc addProcessEntry*(plan: var ProcessPlan, entry: AudioProcessEntry): bool =
  if plan.entryCount >= MaxProcessPlanEntries.uint32:
    plan.capacityExceeded = true
    return false
  plan.entries[plan.entryCount.int] = entry
  inc plan.entryCount
  discard plan.addPluginTarget(entry.pluginId)
  true

proc hasParamTarget(plan: ProcessPlan, pluginId: PluginId, paramId: ParamId): bool =
  for i in 0 ..< plan.paramTargetCount.int:
    let target = plan.paramTargets[i]
    if target.pluginId == pluginId and target.paramId == paramId:
      return true
  false

proc hasEventPortTarget(plan: ProcessPlan, portId: PortId): bool =
  for i in 0 ..< plan.eventPortTargetCount.int:
    if plan.eventPortTargets[i] == portId:
      return true
  false

proc addParamTarget*(
    plan: var ProcessPlan, pluginId: PluginId, paramId: ParamId
): bool =
  if pluginId == NullPluginId or paramId == NullParamId:
    return false
  if plan.hasParamTarget(pluginId, paramId):
    return true
  if plan.paramTargetCount >= MaxProcessPlanParamTargets.uint32:
    plan.capacityExceeded = true
    return false
  plan.paramTargets[plan.paramTargetCount.int] =
    ProcessParamTarget(pluginId: pluginId, paramId: paramId)
  inc plan.paramTargetCount
  true

proc addEventPortTarget*(plan: var ProcessPlan, portId: PortId): bool =
  if portId == NullPortId:
    return false
  if plan.hasEventPortTarget(portId):
    return true
  if plan.eventPortTargetCount >= MaxProcessPlanEventPortTargets.uint32:
    plan.capacityExceeded = true
    return false
  plan.eventPortTargets[plan.eventPortTargetCount.int] = portId
  inc plan.eventPortTargetCount
  true

proc mainAudioPort(
    descriptor: PluginDescriptor, direction: PortDirection
): PluginPortDescriptor =
  for port in descriptor.ports:
    if port.kind == pkAudio and port.direction == direction and port.isMain:
      return port
  for port in descriptor.ports:
    if port.kind == pkAudio and port.direction == direction:
      return port
  PluginPortDescriptor()

proc audioIoModeFor*(descriptor: PluginDescriptor): AudioIoMode =
  let input = mainAudioPort(descriptor, pdIn)
  let output = mainAudioPort(descriptor, pdOut)
  if input.channelCount == 1 and output.channelCount == 1:
    return aimMonoLeftToStereo
  if input.channelCount == 2 and output.channelCount == 2:
    return aimStereo
  aimBypass

proc mainAudioPortForNode(
    m: NilrackModel, nodeId: NodeId, direction: PortDirection
): PortData =
  var fallback: PortData
  for portId in m.portsForNode(nodeId):
    let port = m.portData(portId)
    if port.isNone or port.get.kind != pkAudio or port.get.direction != direction:
      continue
    if port.get.isMain:
      return port.get
    if fallback.id == NullPortId:
      fallback = port.get
  fallback

proc audioIoModeForNode*(m: NilrackModel, nodeId: NodeId): AudioIoMode =
  let input = m.mainAudioPortForNode(nodeId, pdIn)
  let output = m.mainAudioPortForNode(nodeId, pdOut)
  if input.channelCount == 1 and output.channelCount == 1:
    return aimMonoLeftToStereo
  if input.channelCount == 2 and output.channelCount == 2:
    return aimStereo
  aimBypass

proc runtimeForPlugin(store: PluginRuntimeStore, pluginId: PluginId): PluginRuntimeRef =
  for i in 0 ..< store.count.int:
    if store.runtimes[i].pluginId == pluginId:
      return store.runtimes[i]
  PluginRuntimeRef()

proc buildProcessPlanFromCompiledGraph*(
    m: NilrackModel, compiled: ProcessPlan, runtimes: PluginRuntimeStore
): ProcessPlan =
  result = compiled
  result.entryCount = 0
  for i in 0 ..< compiled.nodeCount.int:
    let nodeId = compiled.nodes[i]
    let node = m.nodeData(nodeId)
    if node.isNone or node.get.kind != nkPlugin:
      continue
    let pluginId = m.pluginForNode(nodeId)
    if pluginId.isNone:
      continue
    let plugin = m.pluginData(pluginId.get)
    if plugin.isNone or plugin.get.api != paClap:
      continue
    let runtime = runtimes.runtimeForPlugin(pluginId.get)
    if runtime.runtime.isNil:
      continue
    let mode = m.audioIoModeForNode(nodeId)
    discard result.addProcessEntry(
      AudioProcessEntry(
        nodeId: nodeId,
        pluginId: pluginId.get,
        runtime: runtime.runtime,
        processBlock: clapProcessAudioBlock,
        ioMode: mode,
        active: mode != aimBypass and not node.get.bypassed and not node.get.muted,
      )
    )

proc buildSingleClapProcessPlan*(
    nodeId: NodeId,
    pluginId: PluginId,
    descriptor: PluginDescriptor,
    loaded: ClapLoadedPlugin,
): ProcessPlan =
  discard result.addPlanNode(nodeId)
  let mode = audioIoModeFor(descriptor)
  discard result.addProcessEntry(
    AudioProcessEntry(
      nodeId: nodeId,
      pluginId: pluginId,
      runtime: loaded.clapRuntimePointer(),
      processBlock: clapProcessAudioBlock,
      ioMode: mode,
      active: mode != aimBypass,
    )
  )
