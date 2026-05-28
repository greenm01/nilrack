import std/[options, unittest]

import ../src/state/engine

suite "host audio io ops":
  test "creates JACK input and output nodes with stereo ports":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")

    let io = model.ensureRackAudioIoNodes(rackId)

    check io.inputNode != NullNodeId
    check io.outputNode != NullNodeId
    check model.checkInvariants()

    let input = model.nodeData(io.inputNode)
    let output = model.nodeData(io.outputNode)
    check input.isSome
    check output.isSome
    check input.get.kind == nkInput
    check input.get.name == "JACK Input"
    check output.get.kind == nkOutput
    check output.get.name == "JACK Output"

    var inputOut: PortData
    for portId in model.portIdsForNode(io.inputNode):
      let port = model.portData(portId)
      if port.isSome and port.get.kind == pkAudio and port.get.direction == pdOut:
        inputOut = port.get

    var outputIn: PortData
    for portId in model.portIdsForNode(io.outputNode):
      let port = model.portData(portId)
      if port.isSome and port.get.kind == pkAudio and port.get.direction == pdIn:
        outputIn = port.get

    check inputOut.id != NullPortId
    check inputOut.channelCount == 2
    check inputOut.isMain
    check outputIn.id != NullPortId
    check outputIn.channelCount == 2
    check outputIn.isMain

  test "is idempotent":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")

    let first = model.ensureRackAudioIoNodes(rackId)
    let second = model.ensureRackAudioIoNodes(rackId)

    check second.inputNode == first.inputNode
    check second.outputNode == first.outputNode
    check model.nodes.data.len == 2
    check model.ports.data.len == 2
    check model.checkInvariants()
