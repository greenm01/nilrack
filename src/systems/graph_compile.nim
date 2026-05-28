import ../types/[audio_values, core, graph_values, model]

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

proc setCompiledPlan*(report: var GraphCompileReport, plan: ProcessPlan) =
  report.plan = plan
  if plan.capacityExceeded:
    discard report.reportPlanCapacityExceeded(report.rackId)
