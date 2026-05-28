import std/[options, tables, unittest]

import ../src/state/engine

suite "model invariants":
  test "channel maps are model data and participate in invariants":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    let srcNode = model.nodeCreate(rackId, nkInput, "input")
    let dstNode = model.nodeCreate(rackId, nkOutput, "output")
    let outPort = model.portCreate(srcNode, pkAudio, pdOut, 0, "out", channelCount = 2)
    let inPort = model.portCreate(dstNode, pkAudio, pdIn, 0, "in", channelCount = 1)
    let cableId = model.cableCreate(rackId, outPort, inPort)
    let mapId = model.channelMapCreate(
      rackId, [ChannelMapEntry(srcChannel: 0, dstChannel: 0, gain: 1.0'f32)]
    )

    model.cableSetChannelMap(cableId, mapId)

    check model.checkInvariants()
    check model.cableData(cableId).get.channelMapId == mapId
    check model.cableData(cableId).get.routePolicy == crChannelMap

    model.channelMapDestroy(mapId)

    check model.checkInvariants()
    check model.cableData(cableId).get.channelMapId == NullChannelMapId
    check model.cableData(cableId).get.routePolicy == crAuto

  test "node destroy removes owned records and indexes":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    let srcNode = model.nodeCreate(rackId, nkInput, "input")
    let pluginNode = model.nodeCreate(rackId, nkPlugin, "plugin")
    let outPort = model.portCreate(srcNode, pkAudio, pdOut, 0, "out")
    let inPort = model.portCreate(pluginNode, pkAudio, pdIn, 0, "in")
    let pluginId = model.pluginAttachToNode(
      pluginNode, paClap, "/tmp/example.clap", "dev.nilrack.example", "Example"
    )
    let paramId = model.paramCreate(pluginNode, "Gain", 0.0, 1.0, 0.5)
    let cableId = model.cableCreate(rackId, outPort, inPort)
    let uiId = model.pluginUiCreate(pluginId)
    discard uiId

    model.nodeDestroy(pluginNode)

    check model.checkInvariants()
    check not model.nodes.contains(pluginNode)
    check not model.ports.contains(inPort)
    check not model.params.contains(paramId)
    check not model.plugins.contains(pluginId)
    check not model.cables.contains(cableId)
    check not model.pluginByNode.hasKey(pluginNode)
    check not model.nodeByPlugin.hasKey(pluginId)

  test "plugin detach removes plugin-owned ports params ui and cables":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    let srcNode = model.nodeCreate(rackId, nkInput, "input")
    let pluginNode = model.nodeCreate(rackId, nkPlugin, "plugin")
    let outPort = model.portCreate(srcNode, pkAudio, pdOut, 0, "out")
    let inPort = model.portCreate(pluginNode, pkAudio, pdIn, 0, "in")
    let pluginId = model.pluginAttachToNode(
      pluginNode, paClap, "/tmp/example.clap", "dev.nilrack.example", "Example"
    )
    let paramId = model.paramCreate(pluginNode, "Gain", 0.0, 1.0, 0.5)
    let cableId = model.cableCreate(rackId, outPort, inPort)
    let uiId = model.pluginUiCreate(pluginId)
    discard uiId

    model.pluginDetach(pluginId)

    check model.checkInvariants()
    check model.nodes.contains(pluginNode)
    check not model.plugins.contains(pluginId)
    check not model.ports.contains(inPort)
    check not model.params.contains(paramId)
    check not model.cables.contains(cableId)
    check model.portsByNode[pluginNode].len == 0
    check model.paramsByNode[pluginNode].len == 0

  test "rack destroy removes rack-owned graph data":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    let nodeId = model.nodeCreate(rackId, nkInput, "input")
    let mapId = model.channelMapCreate(
      rackId, [ChannelMapEntry(srcChannel: 0, dstChannel: 0, gain: 1.0'f32)]
    )

    model.rackDestroy(rackId)

    check model.checkInvariants()
    check not model.racks.contains(rackId)
    check not model.nodes.contains(nodeId)
    check not model.channelMaps.contains(mapId)
