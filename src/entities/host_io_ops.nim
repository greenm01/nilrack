import std/options

import ../key_ops
import ../types/core
import ../state/[iterators, model, queries]
import audio_ops
import node_ops

type HostAudioIoNodes* = object
  inputNode*: NodeId
  outputNode*: NodeId

proc firstHostNode(m: NilrackModel, rackId: RackId, kind: NodeKind): NodeId =
  for nodeId in m.nodesInRack(rackId):
    let node = m.nodeData(nodeId)
    if node.isSome and node.get.kind == kind:
      return nodeId
  NullNodeId

proc firstMainAudioPort(
    m: NilrackModel, nodeId: NodeId, direction: PortDirection
): PortId =
  for portId in m.portIdsForNode(nodeId):
    let port = m.portData(portId)
    if port.isSome and port.get.kind == pkAudio and port.get.direction == direction and
        port.get.isMain:
      return portId
  NullPortId

proc ensureHostNode(
    m: var NilrackModel,
    rackId: RackId,
    kind: NodeKind,
    name: string,
    x, y, w, h: float32,
): NodeId =
  result = m.firstHostNode(rackId, kind)
  if result == NullNodeId:
    result = m.nodeCreate(rackId, kind, name)
  m.nodeMove(result, x, y)
  m.nodeResize(result, w, h)

proc ensureRackAudioIoNodes*(m: var NilrackModel, rackId: RackId): HostAudioIoNodes =
  result.inputNode = m.ensureHostNode(
    rackId, nkInput, "JACK Input", 72.0'f32, 128.0'f32, 240.0'f32, 96.0'f32
  )
  result.outputNode = m.ensureHostNode(
    rackId, nkOutput, "JACK Output", 900.0'f32, 128.0'f32, 240.0'f32, 96.0'f32
  )

  if m.firstMainAudioPort(result.inputNode, pdOut) == NullPortId:
    discard m.portCreate(
      result.inputNode, pkAudio, pdOut, 0, "audio out", channelCount = 2, isMain = true
    )

  if m.firstMainAudioPort(result.outputNode, pdIn) == NullPortId:
    discard m.portCreate(
      result.outputNode, pkAudio, pdIn, 0, "audio in", channelCount = 2, isMain = true
    )
