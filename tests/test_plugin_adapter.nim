import std/[options, unittest]

import ../src/plugins/plugin_adapter
import ../src/state/engine
import ../src/types/[core, plugin_values]

suite "plugin adapter":
  test "attaches CLAP metadata to the rack model":
    var model = NilrackModel()
    let descriptor = PluginDescriptor(
      api: paClap,
      path: "/tmp/example.clap",
      uri: "dev.nilrack.example",
      name: "Example",
      vendor: "niltempus",
      version: "1.0.0",
      hasState: true,
      ports:
        @[
          PluginPortDescriptor(
            index: 0,
            externalId: 7,
            name: "Audio In",
            kind: pkAudio,
            direction: pdIn,
            channelCount: 1,
            isMain: true,
          ),
          PluginPortDescriptor(
            index: 0,
            externalId: 8,
            name: "Audio Out",
            kind: pkAudio,
            direction: pdOut,
            channelCount: 1,
            isMain: true,
          ),
        ],
      params:
        @[
          PluginParamDescriptor(
            index: 0,
            externalId: 100,
            name: "Gain",
            modulePath: "Input",
            minVal: -12.0,
            maxVal: 12.0,
            defaultVal: 0.0,
            currentVal: 3.0,
            displayText: "3 dB",
            automatable: true,
          )
        ],
    )

    let attached = model.attachPluginDescriptor(descriptor)

    check attached.rackId != NullRackId
    check attached.nodeId != NullNodeId
    check attached.pluginId != NullPluginId
    check model.racks.data.len == 1
    check model.nodes.data.len == 1
    check model.plugins.data.len == 1
    check model.ports.data.len == 2
    check model.params.data.len == 1

    let plugin = model.plugins.entity(attached.pluginId).get
    check plugin.api == paClap
    check plugin.uri == "dev.nilrack.example"
    check plugin.vendor == "niltempus"
    check plugin.version == "1.0.0"
    check plugin.hasState

    let param = model.params.data[0]
    check param.externalId == 100
    check param.modulePath == "Input"
    check param.currentVal == 3.0
    check param.displayText == "3 dB"
    check param.automatable
