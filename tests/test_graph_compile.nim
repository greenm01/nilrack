import std/unittest

import ../src/systems/graph_compile
import ../src/types/[audio_values, core, graph_values, model]

suite "graph compile errors":
  test "records compile errors as bounded UI data":
    var report = initGraphCompileReport(RackId(1))

    check report.reportCycleDetected(RackId(1), NodeId(2), CableId(3))
    check report.reportPlanCapacityExceeded(RackId(1))
    check report.reportMissingRuntime(RackId(1), NodeId(4), PluginId(5))
    check report.reportUnsupportedRoutePolicy(RackId(1), CableId(6), crSumToMono)

    check report.hasCompileErrors
    check report.errorCount == 4
    check report.errors[0].kind == gceCycleDetected
    check report.errors[0].nodeId == NodeId(2)
    check report.errors[1].kind == gcePlanCapacityExceeded
    check report.errors[2].kind == gceMissingRuntime
    check report.errors[2].pluginId == PluginId(5)
    check report.errors[3].kind == gceUnsupportedRoutePolicy
    check report.errors[3].routePolicy == crSumToMono

  test "reports plan capacity when attaching compiled plan":
    var report = initGraphCompileReport(RackId(7))
    var plan: ProcessPlan
    plan.capacityExceeded = true

    report.setCompiledPlan(plan)

    check report.plan.capacityExceeded
    check report.errorCount == 1
    check report.errors[0].kind == gcePlanCapacityExceeded
    check report.errors[0].rackId == RackId(7)

  test "compile error report uses bounded storage":
    var report = initGraphCompileReport(RackId(1))

    for i in 0 ..< MaxGraphCompileErrors:
      check report.reportMissingRuntime(
        RackId(1), NodeId(i.uint32 + 1), PluginId(i.uint32 + 1)
      )

    check report.errorCount == MaxGraphCompileErrors.uint32
    check not report.reportMissingRuntime(RackId(1), NodeId(999), PluginId(999))
    check report.errorOverflowed
