import std/options

import ../plugins/plugin_runtime_api
import ../key_ops
import ../state/[iterators, model, queries]
import ../types/[audio_values, core]
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

proc addProcessBuffer*(
    plan: var ProcessPlan, slot: ProcessBufferSlot, index: var uint32
): bool =
  for i in 0 ..< plan.bufferCount.int:
    if plan.buffers[i] == slot:
      index = i.uint32
      return true
  if plan.bufferCount >= MaxProcessPlanBuffers.uint32:
    plan.capacityExceeded = true
    return false
  index = plan.bufferCount
  plan.buffers[plan.bufferCount.int] = slot
  inc plan.bufferCount
  true

proc addProcessOp*(plan: var ProcessPlan, op: ProcessPlanOp): bool =
  if plan.opCount >= MaxProcessPlanOps.uint32:
    plan.capacityExceeded = true
    return false
  plan.ops[plan.opCount.int] = op
  inc plan.opCount
  true

proc addClearOp*(plan: var ProcessPlan, dstBuffer: uint32): bool =
  plan.addProcessOp(
    ProcessPlanOp(kind: pokClear, dstBuffer: dstBuffer, channelCount: 1)
  )

proc addCopyOp*(plan: var ProcessPlan, srcBuffer, dstBuffer: uint32): bool =
  plan.addProcessOp(
    ProcessPlanOp(
      kind: pokCopy, srcBuffer: srcBuffer, dstBuffer: dstBuffer, channelCount: 1
    )
  )

proc addAddOp*(plan: var ProcessPlan, srcBuffer, dstBuffer: uint32): bool =
  plan.addProcessOp(
    ProcessPlanOp(
      kind: pokAdd, srcBuffer: srcBuffer, dstBuffer: dstBuffer, channelCount: 1
    )
  )

proc addProcessOp*(
    plan: var ProcessPlan,
    entryIndex, srcBuffer, dstBuffer, channelCount: uint32,
    srcBuffer2: uint32 = 0,
    dstBuffer2: uint32 = 0,
): bool =
  plan.addProcessOp(
    ProcessPlanOp(
      kind: pokProcess,
      srcBuffer: srcBuffer,
      srcBuffer2: srcBuffer2,
      dstBuffer: dstBuffer,
      dstBuffer2: dstBuffer2,
      entryIndex: entryIndex,
      channelCount: channelCount,
    )
  )

proc applyHostNodeState*(plan: var ProcessPlan, node: NodeData) =
  for i in 0 ..< plan.entryCount.int:
    if plan.entries[i].nodeId == node.id:
      plan.entries[i].active =
        plan.entries[i].active and not node.bypassed and not node.muted

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

proc mainAudioPortForNode(
    m: NilrackModel, nodeId: NodeId, direction: PortDirection
): PortData =
  var fallback: PortData
  for portId in m.portIdsForNode(nodeId):
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

proc addHostBuffer(
    plan: var ProcessPlan, kind: ProcessBufferKind, channel: uint32, index: var uint32
): bool =
  plan.addProcessBuffer(ProcessBufferSlot(kind: kind, channel: channel), index)

proc addHostCopyOp(
    plan: var ProcessPlan, srcKind, dstKind: ProcessBufferKind, channel: uint32
): bool =
  var srcIndex: uint32
  var dstIndex: uint32
  result = plan.addHostBuffer(srcKind, channel, srcIndex)
  result = plan.addHostBuffer(dstKind, channel, dstIndex) and result
  result = plan.addCopyOp(srcIndex, dstIndex) and result

proc addHostAddOp(
    plan: var ProcessPlan, srcKind, dstKind: ProcessBufferKind, channel: uint32
): bool =
  var srcIndex: uint32
  var dstIndex: uint32
  result = plan.addHostBuffer(srcKind, channel, srcIndex)
  result = plan.addHostBuffer(dstKind, channel, dstIndex) and result
  result = plan.addAddOp(srcIndex, dstIndex) and result

proc addHostClearOp(
    plan: var ProcessPlan, dstKind: ProcessBufferKind, channel: uint32
): bool =
  var dstIndex: uint32
  result = plan.addHostBuffer(dstKind, channel, dstIndex)
  result = plan.addClearOp(dstIndex) and result

proc pluginEntryIndex(plan: ProcessPlan, nodeId: NodeId): int =
  for i in 0 ..< plan.entryCount.int:
    if plan.entries[i].nodeId == nodeId:
      return i
  -1

proc channelCountForMode(mode: AudioIoMode): uint32 =
  case mode
  of aimBypass: 0
  of aimMonoLeftToStereo: 1
  of aimStereo: 2

proc addHostProcessOp(plan: var ProcessPlan, entryIndex: uint32): bool =
  if entryIndex >= plan.entryCount:
    return false
  let channelCount = channelCountForMode(plan.entries[entryIndex.int].ioMode)
  if channelCount == 0:
    return false

  var inputStart: uint32
  var outputStart: uint32
  var input2: uint32
  var output2: uint32
  result = plan.addHostBuffer(pbkHostInput, 0, inputStart)
  result = plan.addHostBuffer(pbkHostOutput, 0, outputStart) and result
  if channelCount > 1:
    result = plan.addHostBuffer(pbkHostInput, 1, input2) and result
    result = plan.addHostBuffer(pbkHostOutput, 1, output2) and result
  else:
    input2 = inputStart
    result = plan.addHostBuffer(pbkHostOutput, 1, output2) and result
  result =
    plan.addProcessOp(
      entryIndex, inputStart, outputStart, channelCount, input2, output2
    ) and result

proc cableTouchesAudioOutput(
    m: NilrackModel, rackId: RackId, outputNode: NodeId
): bool =
  for cableId in m.cablesInRack(rackId):
    let cable = m.cableData(cableId)
    if cable.isNone:
      continue
    let dstPort = m.portData(cable.get.dstPort)
    if dstPort.isSome and dstPort.get.nodeId == outputNode and
        dstPort.get.kind == pkAudio:
      return true
  false

proc addHostCableOps(plan: var ProcessPlan, m: NilrackModel, rackId: RackId) =
  var outputWritten: array[2, bool]
  for cableId in m.cablesInRack(rackId):
    let cable = m.cableData(cableId)
    if cable.isNone:
      continue
    let srcPort = m.portData(cable.get.srcPort)
    let dstPort = m.portData(cable.get.dstPort)
    if srcPort.isNone or dstPort.isNone:
      continue
    if srcPort.get.kind != pkAudio or dstPort.get.kind != pkAudio:
      continue
    let srcNode = m.nodeData(srcPort.get.nodeId)
    let dstNode = m.nodeData(dstPort.get.nodeId)
    if srcNode.isNone or dstNode.isNone:
      continue
    if srcNode.get.kind != nkInput or dstNode.get.kind != nkOutput:
      continue

    let channels = min(srcPort.get.channelCount, dstPort.get.channelCount)
    for channel in 0'u32 ..< min(channels, 2'u32):
      if outputWritten[channel.int]:
        discard plan.addHostAddOp(pbkHostInput, pbkHostOutput, channel)
      else:
        discard plan.addHostCopyOp(pbkHostInput, pbkHostOutput, channel)
        outputWritten[channel.int] = true

  for nodeId in m.nodesInRack(rackId):
    let node = m.nodeData(nodeId)
    if node.isNone or node.get.kind != nkOutput:
      continue
    if m.cableTouchesAudioOutput(rackId, nodeId):
      continue
    let output = m.mainAudioPortForNode(nodeId, pdIn)
    if output.id == NullPortId or output.kind != pkAudio:
      continue
    for channel in 0'u32 ..< min(output.channelCount, 2'u32):
      discard plan.addHostClearOp(pbkHostOutput, channel)

proc rackForCompiledPlan(m: NilrackModel, compiled: ProcessPlan): RackId =
  for i in 0 ..< compiled.nodeCount.int:
    let node = m.nodeData(compiled.nodes[i])
    if node.isSome:
      return node.get.rackId
  NullRackId

proc buildProcessPlanFromCompiledGraph*(
    m: NilrackModel, compiled: ProcessPlan, runtimes: PluginRuntimeStore
): ProcessPlan =
  result = compiled
  result.entryCount = 0
  result.bufferCount = 0
  result.opCount = 0
  for i in 0 ..< compiled.nodeCount.int:
    let nodeId = compiled.nodes[i]
    let node = m.nodeData(nodeId)
    if node.isNone or node.get.kind != nkPlugin:
      continue
    let pluginId = m.pluginForNode(nodeId)
    if pluginId.isNone:
      continue
    let runtime = runtimes.runtimeForPlugin(pluginId.get)
    if not runtime.hasRuntimeProcess:
      continue
    let mode = m.audioIoModeForNode(nodeId)
    discard result.addProcessEntry(
      AudioProcessEntry(
        nodeId: nodeId,
        pluginId: pluginId.get,
        runtime: runtime.runtime,
        ops: runtime.ops,
        ioMode: mode,
        active: mode != aimBypass and not node.get.bypassed and not node.get.muted,
      )
    )

  let rackId = m.rackForCompiledPlan(compiled)
  if rackId != NullRackId:
    result.addHostCableOps(m, rackId)

  for i in 0 ..< compiled.nodeCount.int:
    let entryIndex = result.pluginEntryIndex(compiled.nodes[i])
    if entryIndex >= 0:
      discard result.addHostProcessOp(entryIndex.uint32)
