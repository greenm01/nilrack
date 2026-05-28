import std/unittest

import ../src/state/engine
import ../src/systems/graph_compile
import ../src/types/[audio_values, core, graph_values, plugin_runtime_values]

proc testProcessBlock(
    runtime: pointer, in1, in2, out1, out2: pointer, nframes: uint32, mode: AudioIoMode
): bool {.nimcall, gcsafe, raises: [].} =
  discard runtime
  discard in1
  discard in2
  discard out1
  discard out2
  discard nframes
  discard mode
  true

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

  test "compiles one rack in acyclic cable order":
    var model = NilrackModel()
    var runtimes: PluginRuntimeStore
    let rackId = model.rackCreate("rack")
    let inputNode = model.nodeCreate(rackId, nkInput, "input")
    let pluginNode = model.nodeCreate(rackId, nkPlugin, "plugin")
    let outputNode = model.nodeCreate(rackId, nkOutput, "output")
    let inputOut = model.portCreate(inputNode, pkAudio, pdOut, 0, "out")
    let pluginIn = model.portCreate(pluginNode, pkAudio, pdIn, 0, "in")
    let pluginOut = model.portCreate(pluginNode, pkAudio, pdOut, 0, "out")
    let outputIn = model.portCreate(outputNode, pkAudio, pdIn, 0, "in")
    let pluginId = model.pluginAttachToNode(
      pluginNode, paClap, "/tmp/example.clap", "dev.nilrack.example", "Example"
    )
    discard model.paramCreate(pluginNode, "Gain", 0.0, 1.0, 0.5)
    runtimes.runtimes[0] = PluginRuntimeRef(
      pluginId: pluginId,
      runtime: cast[pointer](1),
      ops: cast[ptr PluginRuntimeOps](1),
      processBlock: testProcessBlock,
    )
    runtimes.count = 1

    discard model.cableCreate(rackId, inputOut, pluginIn)
    discard model.cableCreate(rackId, pluginOut, outputIn)

    let report = model.compileRackGraph(rackId, runtimes)

    check not report.hasCompileErrors
    check report.plan.nodeCount == 3
    check report.plan.nodes[0] == inputNode
    check report.plan.nodes[1] == pluginNode
    check report.plan.nodes[2] == outputNode
    check report.plan.pluginTargetCount == 1
    check report.plan.pluginTargets[0] == pluginId
    check report.plan.paramTargetCount == 1

  test "rejects missing plugin runtime":
    var model = NilrackModel()
    var runtimes: PluginRuntimeStore
    let rackId = model.rackCreate("rack")
    let pluginNode = model.nodeCreate(rackId, nkPlugin, "plugin")
    let pluginId = model.pluginAttachToNode(
      pluginNode, paClap, "/tmp/example.clap", "dev.nilrack.example", "Example"
    )

    let report = model.compileRackGraph(rackId, runtimes)

    check report.hasCompileErrors
    check report.errorCount == 1
    check report.errors[0].kind == gceMissingRuntime
    check report.errors[0].pluginId == pluginId

  test "rejects cycles and unsupported route policies":
    var model = NilrackModel()
    var runtimes: PluginRuntimeStore
    let rackId = model.rackCreate("rack")
    let nodeA = model.nodeCreate(rackId, nkInput, "a")
    let nodeB = model.nodeCreate(rackId, nkOutput, "b")
    let aIn = model.portCreate(nodeA, pkAudio, pdIn, 0, "a in")
    let aOut = model.portCreate(nodeA, pkAudio, pdOut, 0, "a out")
    let bIn = model.portCreate(nodeB, pkAudio, pdIn, 0, "b in")
    let bOut = model.portCreate(nodeB, pkAudio, pdOut, 0, "b out")
    let cycleCable = model.cableCreate(rackId, aOut, bIn)
    let policyCable = model.cableCreate(rackId, bOut, aIn)
    model.cableSetRoutePolicy(policyCable, crSumToMono)

    let report = model.compileRackGraph(rackId, runtimes)

    check report.hasCompileErrors
    check report.errors[0].kind == gceUnsupportedRoutePolicy
    check report.errors[0].cableId == policyCable

    model.cableSetRoutePolicy(policyCable, crAuto)
    let cycleReport = model.compileRackGraph(rackId, runtimes)
    check cycleReport.hasCompileErrors
    check cycleReport.errors[0].kind == gceCycleDetected
    check cycleReport.errors[0].cableId in [cycleCable, policyCable]

  test "reports invalid cable endpoints direction and kind":
    var model = NilrackModel()
    var runtimes: PluginRuntimeStore
    let rackId = model.rackCreate("rack")
    let nodeA = model.nodeCreate(rackId, nkInput, "a")
    let nodeB = model.nodeCreate(rackId, nkOutput, "b")
    let audioIn = model.portCreate(nodeA, pkAudio, pdIn, 0, "audio in")
    let midiOut = model.portCreate(nodeA, pkMidi, pdOut, 0, "midi out")
    let audioOut = model.portCreate(nodeB, pkAudio, pdOut, 0, "audio out")
    let audioInB = model.portCreate(nodeB, pkAudio, pdIn, 0, "audio in b")

    let badDirection = model.cableCreate(rackId, audioIn, audioInB)
    let badKind = model.cableCreate(rackId, midiOut, audioInB)
    discard model.cableCreate(rackId, PortId(999), audioInB)
    discard audioOut

    let report = model.compileRackGraph(rackId, runtimes)

    check report.hasCompileErrors
    check report.errors[0].kind == gceDirectionMismatch
    check report.errors[0].cableId == badDirection
    check report.errors[1].kind == gceKindMismatch
    check report.errors[1].cableId == badKind
    check report.errors[2].kind == gceMissingPort
    check report.errors[2].portId == PortId(999)
