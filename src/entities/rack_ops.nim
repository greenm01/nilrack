import std/tables
import ../types/core
import ../state/[entity_manager, id_gen, model]
import node_ops

proc rackCreate*(m: var NilrackModel, name: string): RackId =
  let id = m.counters.generateRackId()
  m.racks.insert(RackData(id: id, name: name))
  m.nodesByRack[id] = @[]
  m.cablesByRack[id] = @[]
  m.channelMapsByRack[id] = @[]
  id

proc firstRackIdOrCreateDefault*(m: var NilrackModel): RackId =
  if m.racks.data.len > 0:
    return m.racks.data[0].id
  m.rackCreate("default")

proc rackDestroy*(m: var NilrackModel, id: RackId) =
  for nodeId in m.nodesByRack.getOrDefault(id, @[]):
    m.nodeDestroy(nodeId)
  for cableId in m.cablesByRack.getOrDefault(id, @[]):
    discard m.cables.delete(cableId)
  for channelMapId in m.channelMapsByRack.getOrDefault(id, @[]):
    discard m.channelMaps.delete(channelMapId)
  m.nodesByRack.del(id)
  m.cablesByRack.del(id)
  m.channelMapsByRack.del(id)
  discard m.racks.delete(id)
