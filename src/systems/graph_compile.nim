import std/[options, tables]

import ../state/[iterators, model, queries]
import ../types/[audio_values, core, graph_values, plugin_runtime_values]
import graph_process_plan

proc initGraphCompileReport*(rackId: RackId): GraphCompileReport =
  result.rackId = rackId

proc addCompileError*(report: var GraphCompileReport, error: GraphCompileError): bool =
  if report.errorCount >= MaxGraphCompileErrors.uint32:
    report.errorOverflowed = true
    return false
  report.errors[report.errorCount.int] = error
  inc report.errorCount
  true

proc hasCompileErrors*(report: GraphCompileReport): bool =
  report.errorCount > 0 or report.errorOverflowed

proc reportCycleDetected*(
    report: var GraphCompileReport, rackId: RackId, nodeId: NodeId, cableId: CableId
): bool =
  report.addCompileError(
    GraphCompileError(
      kind: gceCycleDetected, rackId: rackId, nodeId: nodeId, cableId: cableId
    )
  )

proc reportPlanCapacityExceeded*(report: var GraphCompileReport, rackId: RackId): bool =
  report.addCompileError(
    GraphCompileError(kind: gcePlanCapacityExceeded, rackId: rackId)
  )

proc reportMissingRuntime*(
    report: var GraphCompileReport, rackId: RackId, nodeId: NodeId, pluginId: PluginId
): bool =
  report.addCompileError(
    GraphCompileError(
      kind: gceMissingRuntime, rackId: rackId, nodeId: nodeId, pluginId: pluginId
    )
  )

proc reportUnsupportedRoutePolicy*(
    report: var GraphCompileReport,
    rackId: RackId,
    cableId: CableId,
    routePolicy: CableRoutePolicy,
): bool =
  report.addCompileError(
    GraphCompileError(
      kind: gceUnsupportedRoutePolicy,
      rackId: rackId,
      cableId: cableId,
      routePolicy: routePolicy,
    )
  )

proc reportMissingPort*(
    report: var GraphCompileReport, rackId: RackId, cableId: CableId, portId: PortId
): bool =
  report.addCompileError(
    GraphCompileError(
      kind: gceMissingPort, rackId: rackId, cableId: cableId, portId: portId
    )
  )

proc reportDirectionMismatch*(
    report: var GraphCompileReport, rackId: RackId, cableId: CableId
): bool =
  report.addCompileError(
    GraphCompileError(kind: gceDirectionMismatch, rackId: rackId, cableId: cableId)
  )

proc reportKindMismatch*(
    report: var GraphCompileReport, rackId: RackId, cableId: CableId
): bool =
  report.addCompileError(
    GraphCompileError(kind: gceKindMismatch, rackId: rackId, cableId: cableId)
  )

proc setCompiledPlan*(report: var GraphCompileReport, plan: ProcessPlan) =
  report.plan = plan
  if plan.capacityExceeded:
    discard report.reportPlanCapacityExceeded(report.rackId)

proc hasPluginRuntime(store: PluginRuntimeStore, pluginId: PluginId): bool =
  for i in 0 ..< store.count.int:
    let runtime = store.runtimes[i]
    if runtime.pluginId == pluginId and not runtime.runtime.isNil and
        not runtime.ops.isNil and not runtime.processBlock.isNil:
      return true
  false

proc nodeIndex(nodes: openArray[NodeId], nodeId: NodeId): int =
  for i, candidate in nodes:
    if candidate == nodeId:
      return i
  -1

proc compileRackGraph*(
    m: NilrackModel, rackId: RackId, runtimes: PluginRuntimeStore
): GraphCompileReport =
  result = initGraphCompileReport(rackId)

  var nodeIds: seq[NodeId]
  for nodeId in m.nodesInRack(rackId):
    nodeIds.add(nodeId)

  var outgoing: Table[NodeId, seq[(NodeId, CableId)]]
  var indegree: Table[NodeId, int]
  for nodeId in nodeIds:
    indegree[nodeId] = 0

  for cableId in m.cablesInRack(rackId):
    let cable = m.cableData(cableId)
    if cable.isNone:
      continue
    let cableValue = cable.get
    if cableValue.routePolicy != crAuto:
      discard
        result.reportUnsupportedRoutePolicy(rackId, cableId, cableValue.routePolicy)
      continue

    let srcPort = m.portData(cableValue.srcPort)
    let dstPort = m.portData(cableValue.dstPort)
    if srcPort.isNone:
      discard result.reportMissingPort(rackId, cableId, cableValue.srcPort)
      continue
    if dstPort.isNone:
      discard result.reportMissingPort(rackId, cableId, cableValue.dstPort)
      continue
    if srcPort.get.direction != pdOut or dstPort.get.direction != pdIn:
      discard result.reportDirectionMismatch(rackId, cableId)
      continue
    if srcPort.get.kind != dstPort.get.kind:
      discard result.reportKindMismatch(rackId, cableId)
      continue
    let srcNode = srcPort.get.nodeId
    let dstNode = dstPort.get.nodeId
    if nodeIds.nodeIndex(srcNode) < 0 or nodeIds.nodeIndex(dstNode) < 0:
      discard result.reportMissingPort(rackId, cableId, cableValue.srcPort)
      continue

    outgoing.mgetOrPut(srcNode, @[]).add((dstNode, cableId))
    indegree[dstNode] = indegree.getOrDefault(dstNode, 0) + 1

  var ready: seq[NodeId]
  for nodeId in nodeIds:
    if indegree.getOrDefault(nodeId, 0) == 0:
      ready.add(nodeId)

  var ordered: seq[NodeId]
  var readyIndex = 0
  while readyIndex < ready.len:
    let nodeId = ready[readyIndex]
    inc readyIndex
    ordered.add(nodeId)
    for edge in outgoing.getOrDefault(nodeId, @[]):
      let dstNode = edge[0]
      indegree[dstNode] = indegree[dstNode] - 1
      if indegree[dstNode] == 0:
        ready.add(dstNode)

  if ordered.len != nodeIds.len:
    for cableId in m.cablesInRack(rackId):
      let cable = m.cableData(cableId)
      if cable.isNone:
        continue
      let dstPort = m.portData(cable.get.dstPort)
      if dstPort.isSome and indegree.getOrDefault(dstPort.get.nodeId, 0) > 0:
        discard result.reportCycleDetected(rackId, dstPort.get.nodeId, cableId)
        break

  var plan: ProcessPlan
  for nodeId in ordered:
    discard plan.addPlanNode(nodeId)
    let pluginId = m.pluginForNode(nodeId)
    if pluginId.isNone:
      continue
    if not runtimes.hasPluginRuntime(pluginId.get):
      discard result.reportMissingRuntime(rackId, nodeId, pluginId.get)
      continue
    discard plan.addPluginTarget(pluginId.get)
    for paramId in m.paramsForNode(nodeId):
      discard plan.addParamTarget(pluginId.get, paramId)
    for portId in m.portsForNode(nodeId):
      let port = m.portData(portId)
      if port.isSome and port.get.kind != pkAudio and port.get.direction == pdIn:
        discard plan.addEventPortTarget(portId)

  if not result.hasCompileErrors:
    result.setCompiledPlan(plan)
