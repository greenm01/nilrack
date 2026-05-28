import std/[options, tables]
import ../types/core
import model
import entity_manager

iterator nodes*(m: NilrackModel): NodeData =
  for node in m.nodes.data:
    yield node

iterator pluginNodes*(m: NilrackModel): NodeData =
  for node in m.nodes.data:
    if node.kind == nkPlugin:
      yield node

iterator nodesInRack*(m: NilrackModel, id: RackId): NodeId =
  for nodeId in m.nodesByRack.getOrDefault(id, @[]):
    yield nodeId

iterator cablesInRack*(m: NilrackModel, id: RackId): CableId =
  for cableId in m.cablesByRack.getOrDefault(id, @[]):
    yield cableId

iterator channelMapsInRack*(m: NilrackModel, id: RackId): ChannelMapId =
  for channelMapId in m.channelMapsByRack.getOrDefault(id, @[]):
    yield channelMapId

iterator audioPortsForNode*(m: NilrackModel, id: NodeId): PortId =
  for portId in m.portsByNode.getOrDefault(id, @[]):
    let p = m.ports.entity(portId)
    if p.isSome and p.get.kind == pkAudio:
      yield portId

iterator portIdsForNode*(m: NilrackModel, id: NodeId): PortId =
  for portId in m.portsByNode.getOrDefault(id, @[]):
    yield portId

iterator paramsForNode*(m: NilrackModel, id: NodeId): ParamId =
  for paramId in m.paramsByNode.getOrDefault(id, @[]):
    yield paramId

iterator paramIdsForNode*(m: NilrackModel, id: NodeId): ParamId =
  for paramId in m.paramsByNode.getOrDefault(id, @[]):
    yield paramId
