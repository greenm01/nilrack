import std/[os, unittest]

import ../src/audio/process_plan_audio
import ../src/audio/process_plan_targets
import ../src/plugins/clap_host
import ../src/plugins/plugin_adapter
import ../src/state/engine
import ../src/systems/graph_process_plan
import ../src/types/[audio_values, core, plugin_values]

proc localClapPath(): string =
  let envPath = getEnv("NILRACK_TEST_CLAP")
  if envPath.len > 0:
    return envPath
  let nilamp = "/home/niltempus/dev/nilamp/native/bin/nilamp-twd-mkii.clap"
  if fileExists(nilamp):
    return nilamp
  ""

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
        check loaded.plugin.activateClap(48000.0, 1, 64)
        check loaded.plugin.startClapProcessing()

        var plan = buildSingleClapProcessPlan(
          NodeId(1), PluginId(1), loaded.descriptor, loaded.plugin
        )
        check plan.nodeCount == 1
        check plan.nodes[0] == NodeId(1)
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
