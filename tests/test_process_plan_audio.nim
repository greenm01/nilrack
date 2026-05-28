import std/[os, unittest]

import ../src/audio/process_plan_audio
import ../src/audio/process_plan_targets
import ../src/plugins/plugin_runtime_api
import ../src/plugins/clap_host
import ../src/plugins/plugin_adapter
import ../src/state/engine
import ../src/systems/graph_compile
import ../src/systems/graph_process_plan
import ../src/systems/plugin_lifecycle
import ../src/types/[audio_values, core, plugin_runtime_values, plugin_values]

proc localClapPath(): string =
  let envPath = getEnv("NILRACK_TEST_CLAP")
  if envPath.len > 0:
    return envPath
  let nilamp = "/home/niltempus/dev/nilamp/native/bin/nilamp-twd-mkii.clap"
  if fileExists(nilamp):
    return nilamp
  ""

proc testProcess(
    runtime: pointer, context: ptr ProcessContext
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  discard runtime
  discard context
  prsOk

type CountingRuntime = object
  calls: int

proc copyPlusOneProcess(
    runtime: pointer, context: ptr ProcessContext
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  let state = cast[ptr CountingRuntime](runtime)
  inc state.calls
  let inputBus = context.audioInputs[0]
  let outputBus = context.audioOutputs[0]
  for channel in 0'u32 ..< inputBus.channelCount:
    let input = cast[ptr UncheckedArray[float32]](inputBus.channels[channel.int])
    let output = cast[ptr UncheckedArray[float32]](outputBus.channels[channel.int])
    for frame in 0 ..< context.frames.int:
      output[frame] = input[frame] + 1.0'f32
  prsOk

suite "process plan audio":
  test "process plan nodes use bounded storage":
    var plan: ProcessPlan
    for i in 0 ..< MaxProcessPlanNodes:
      check plan.addPlanNode(NodeId(i.uint32 + 1))

    check plan.nodeCount == MaxProcessPlanNodes.uint32
    check plan.nodes[0] == NodeId(1)
    check plan.nodes[MaxProcessPlanNodes - 1] == NodeId(MaxProcessPlanNodes.uint32)
    check not plan.addPlanNode(NodeId(999))
    check plan.capacityExceeded
    check plan.nodeCount == MaxProcessPlanNodes.uint32

  test "process plan entries use bounded storage":
    var plan: ProcessPlan
    for i in 0 ..< MaxProcessPlanEntries:
      check plan.addProcessEntry(AudioProcessEntry(nodeId: NodeId(i.uint32 + 1)))

    check plan.entryCount == MaxProcessPlanEntries.uint32
    check plan.entries[0].nodeId == NodeId(1)
    check plan.entries[MaxProcessPlanEntries - 1].nodeId ==
      NodeId(MaxProcessPlanEntries.uint32)
    check not plan.addProcessEntry(AudioProcessEntry(nodeId: NodeId(999)))
    check plan.capacityExceeded
    check plan.entryCount == MaxProcessPlanEntries.uint32

  test "process plan buffers and ops use bounded storage":
    var plan: ProcessPlan
    var index: uint32
    check plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostInput, channel: 0), index
    )
    check index == 0
    check plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostInput, channel: 0), index
    )
    check index == 0
    check plan.bufferCount == 1

    for i in 1 ..< MaxProcessPlanBuffers:
      check plan.addProcessBuffer(
        ProcessBufferSlot(kind: pbkHostInput, channel: i.uint32), index
      )

    check plan.bufferCount == MaxProcessPlanBuffers.uint32
    check not plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostOutput, channel: 99), index
    )
    check plan.capacityExceeded

    var opPlan: ProcessPlan
    for i in 0 ..< MaxProcessPlanOps:
      check opPlan.addCopyOp(0, 1)

    check opPlan.opCount == MaxProcessPlanOps.uint32
    check not opPlan.addCopyOp(0, 1)
    check opPlan.capacityExceeded

  test "process plan target lookup uses bounded storage":
    var plan: ProcessPlan
    check plan.addPluginTarget(PluginId(1))
    check plan.addPluginTarget(PluginId(1))
    check plan.pluginTargetCount == 1

    for i in 0 ..< MaxProcessPlanParamTargets:
      check plan.addParamTarget(PluginId(1), ParamId(i.uint32 + 1))

    check plan.paramTargetCount == MaxProcessPlanParamTargets.uint32
    check not plan.addParamTarget(PluginId(1), ParamId(9999))
    check plan.capacityExceeded

    var portPlan: ProcessPlan
    for i in 0 ..< MaxProcessPlanEventPortTargets:
      check portPlan.addEventPortTarget(PortId(i.uint32 + 1))

    check portPlan.eventPortTargetCount == MaxProcessPlanEventPortTargets.uint32
    check not portPlan.addEventPortTarget(PortId(9999))
    check portPlan.capacityExceeded

  test "process plan target lookup rejects stale targets":
    var plan: ProcessPlan
    check plan.addPluginTarget(PluginId(1))
    check plan.addParamTarget(PluginId(1), ParamId(10))
    check plan.addEventPortTarget(PortId(20))

    check hasLivePluginTarget(addr plan, PluginId(1))
    check not hasLivePluginTarget(addr plan, PluginId(2))
    check hasParamTarget(addr plan, PluginId(1), ParamId(10))
    check not hasParamTarget(addr plan, PluginId(2), ParamId(10))
    check not hasParamTarget(addr plan, PluginId(1), ParamId(11))
    check hasEventPortTarget(addr plan, PortId(20))
    check not hasEventPortTarget(addr plan, PortId(21))

  test "compiled model plan carries plugin parameter and event port targets":
    var model = NilrackModel()
    let descriptor = PluginDescriptor(
      api: paClap,
      path: "/tmp/example.clap",
      uri: "dev.nilrack.example",
      name: "Example",
      ports:
        @[
          PluginPortDescriptor(
            index: 0, externalId: 7, name: "MIDI In", kind: pkMidi, direction: pdIn
          )
        ],
      params:
        @[
          PluginParamDescriptor(
            index: 0,
            externalId: 100,
            name: "Gain",
            minVal: 0.0,
            maxVal: 1.0,
            defaultVal: 0.5,
            currentVal: 0.5,
          )
        ],
    )
    let attached = model.attachPluginDescriptor(descriptor)
    let paramId = model.params.data[0].id
    let portId = model.ports.data[0].id

    var plan = model.compileProcessPlan()
    check hasLivePluginTarget(addr plan, attached.pluginId)
    check hasParamTarget(addr plan, attached.pluginId, paramId)
    check hasEventPortTarget(addr plan, portId)

  test "builds process entries from compiled graph and runtime store":
    var model = NilrackModel()
    var runtimes: PluginRuntimeStore
    let rackId = model.rackCreate("rack")
    let pluginNode = model.nodeCreate(rackId, nkPlugin, "plugin")
    discard model.portCreate(
      pluginNode, pkAudio, pdIn, 0, "in", channelCount = 1, isMain = true
    )
    discard model.portCreate(
      pluginNode, pkAudio, pdOut, 0, "out", channelCount = 1, isMain = true
    )
    let pluginId = model.pluginAttachToNode(
      pluginNode, paClap, "/tmp/example.clap", "dev.nilrack.example", "Example"
    )
    var ops = PluginRuntimeOps(process: testProcess)
    runtimes.runtimes[0] = PluginRuntimeRef(
      pluginId: pluginId, runtime: cast[pointer](1), ops: cast[pointer](addr ops)
    )
    runtimes.count = 1

    let compiled = model.compileRackGraph(rackId, runtimes)
    let plan = model.buildProcessPlanFromCompiledGraph(compiled.plan, runtimes)

    check not compiled.hasCompileErrors
    check plan.nodeCount == 1
    check plan.entryCount == 1
    check plan.entries[0].nodeId == pluginNode
    check plan.entries[0].pluginId == pluginId
    check plan.entries[0].runtime == cast[pointer](1)
    check plan.entries[0].ops == cast[pointer](addr ops)
    check plan.entries[0].ioMode == aimMonoLeftToStereo
    check plan.entries[0].active
    check plan.opCount == 1
    check plan.ops[0].kind == pokProcess
    check plan.ops[0].entryIndex == 0

  test "compiled graph process entries respect host bypass":
    var model = NilrackModel()
    var runtimes: PluginRuntimeStore
    let rackId = model.rackCreate("rack")
    let pluginNode = model.nodeCreate(rackId, nkPlugin, "plugin")
    discard model.portCreate(
      pluginNode, pkAudio, pdIn, 0, "in", channelCount = 1, isMain = true
    )
    discard model.portCreate(
      pluginNode, pkAudio, pdOut, 0, "out", channelCount = 1, isMain = true
    )
    let pluginId = model.pluginAttachToNode(
      pluginNode, paClap, "/tmp/example.clap", "dev.nilrack.example", "Example"
    )
    model.nodes.mEntity(pluginNode).bypassed = true
    var ops = PluginRuntimeOps(process: testProcess)
    runtimes.runtimes[0] = PluginRuntimeRef(
      pluginId: pluginId, runtime: cast[pointer](1), ops: cast[pointer](addr ops)
    )
    runtimes.count = 1

    let compiled = model.compileRackGraph(rackId, runtimes)
    let plan = model.buildProcessPlanFromCompiledGraph(compiled.plan, runtimes)

    check plan.entryCount == 1
    check not plan.entries[0].active

  test "copy op routes host input to host output":
    var plan: ProcessPlan
    var inputIndex: uint32
    var outputIndex: uint32
    check plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostInput, channel: 0), inputIndex
    )
    check plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostOutput, channel: 0), outputIndex
    )
    check plan.addCopyOp(inputIndex, outputIndex)

    var input1: array[4, float32]
    var input2: array[4, float32]
    var output1: array[4, float32]
    var output2: array[4, float32]
    for i in 0 .. input1.high:
      input1[i] = (i + 2).float32
      input2[i] = -10.0'f32

    check processAudioBlock(
      addr plan, addr input1[0], addr input2[0], addr output1[0], addr output2[0], 4
    )
    check output1 == input1
    check output2 == default(array[4, float32])

  test "add op sums into host output":
    var plan: ProcessPlan
    var inputIndex: uint32
    var outputIndex: uint32
    check plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostInput, channel: 0), inputIndex
    )
    check plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostOutput, channel: 0), outputIndex
    )
    check plan.addCopyOp(inputIndex, outputIndex)
    check plan.addAddOp(inputIndex, outputIndex)

    var input1: array[4, float32]
    var input2: array[4, float32]
    var output1: array[4, float32]
    var output2: array[4, float32]
    for i in 0 .. input1.high:
      input1[i] = (i + 1).float32

    check processAudioBlock(
      addr plan, addr input1[0], addr input2[0], addr output1[0], addr output2[0], 4
    )
    for i in 0 .. output1.high:
      check output1[i] == input1[i] * 2.0'f32
    check output2 == default(array[4, float32])

  test "process op uses the selected entry":
    var state: CountingRuntime
    var ops = PluginRuntimeOps(process: copyPlusOneProcess)
    var plan: ProcessPlan
    check plan.addProcessEntry(
      AudioProcessEntry(
        nodeId: NodeId(1),
        pluginId: PluginId(1),
        runtime: nil,
        ops: nil,
        ioMode: aimMonoLeftToStereo,
        active: true,
      )
    )
    check plan.addProcessEntry(
      AudioProcessEntry(
        nodeId: NodeId(2),
        pluginId: PluginId(2),
        runtime: addr state,
        ops: cast[pointer](addr ops),
        ioMode: aimMonoLeftToStereo,
        active: true,
      )
    )
    var inputIndex: uint32
    var outputIndex: uint32
    var outputRightIndex: uint32
    check plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostInput, channel: 0), inputIndex
    )
    check plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostOutput, channel: 0), outputIndex
    )
    check plan.addProcessBuffer(
      ProcessBufferSlot(kind: pbkHostOutput, channel: 1), outputRightIndex
    )
    check plan.addProcessOp(1, inputIndex, outputIndex, 1, inputIndex, outputRightIndex)

    var input1: array[4, float32]
    var input2: array[4, float32]
    var output1: array[4, float32]
    var output2: array[4, float32]
    for i in 0 .. input1.high:
      input1[i] = i.float32

    check processAudioBlock(
      addr plan, addr input1[0], addr input2[0], addr output1[0], addr output2[0], 4
    )
    check state.calls == 1
    for i in 0 .. output1.high:
      check output1[i] == input1[i] + 1.0'f32
      check output2[i] == output1[i]

  test "falls back to passthrough without a plan":
    var input1: array[8, float32]
    var input2: array[8, float32]
    var output1: array[8, float32]
    var output2: array[8, float32]
    for i in 0 .. input1.high:
      input1[i] = i.float32
      input2[i] = -i.float32

    check not processAudioBlock(
      nil, addr input1[0], addr input2[0], addr output1[0], addr output2[0], 8
    )
    check output1 == input1
    check output2 == input2

  let pluginPath = localClapPath()
  if pluginPath.len == 0:
    echo "SKIP: no CLAP plugin found; set NILRACK_TEST_CLAP"
  else:
    test "processes mono CLAP output to both JACK channels":
      let loaded = loadClapPlugin(pluginPath)
      check loaded.ok
      if loaded.ok:
        var model = NilrackModel()
        var runtimes: PluginRuntimeStore
        let attached = model.attachPluginDescriptor(loaded.descriptor)
        let runtime = loaded.plugin.clapPluginRuntimeRef(attached.pluginId)
        check runtimes.addPluginRuntime(runtime)
        check loaded.plugin.activateClap(48000.0, 1, 64)
        check loaded.plugin.startClapProcessing()

        let compiled = model.compileRackGraph(attached.rackId, runtimes)
        var plan = model.buildProcessPlanFromCompiledGraph(compiled.plan, runtimes)
        check not compiled.hasCompileErrors
        check plan.nodeCount == 1
        check plan.nodes[0] == attached.nodeId
        check plan.entryCount == 1
        check plan.entries[0].ioMode == aimMonoLeftToStereo

        var input1: array[64, float32]
        var input2: array[64, float32]
        var output1: array[64, float32]
        var output2: array[64, float32]
        for i in 0 .. input1.high:
          input1[i] = (i.float32 / 64.0'f32) * 0.05'f32
          input2[i] = -input1[i]

        check processAudioBlock(
          addr plan,
          addr input1[0],
          addr input2[0],
          addr output1[0],
          addr output2[0],
          64,
        )
        for i in 0 .. output1.high:
          check output1[i] == output2[i]

        loaded.plugin.stopClapProcessing()
        loaded.plugin.deactivateClap()
        loaded.plugin.close()
