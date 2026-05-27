import std/[options, tables]
import ../types/core
import model
import entity_manager

iterator nodesInRack*(m: NilrackModel, id: RackId): NodeId =
  for nodeId in m.nodesByRack.getOrDefault(id, @[]):
    yield nodeId

iterator cablesInRack*(m: NilrackModel, id: RackId): CableId =
  for cableId in m.cablesByRack.getOrDefault(id, @[]):
    yield cableId

iterator audioPortsForNode*(m: NilrackModel, id: NodeId): PortId =
  for portId in m.portsByNode.getOrDefault(id, @[]):
    let p = m.ports.entity(portId)
    if p.isSome and p.get.kind == pkAudio:
      yield portId

iterator paramsForNode*(m: NilrackModel, id: NodeId): ParamId =
  for paramId in m.paramsByNode.getOrDefault(id, @[]):
    yield paramId
