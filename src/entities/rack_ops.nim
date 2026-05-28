import std/tables
import ../types/core
import ../state/[entity_manager, id_gen, model]

proc rackCreate*(m: var NilrackModel, name: string): RackId =
  let id = m.counters.generateRackId()
  m.racks.insert(RackData(id: id, name: name))
  m.nodesByRack[id] = @[]
  m.cablesByRack[id] = @[]
  id

proc firstRackIdOrCreateDefault*(m: var NilrackModel): RackId =
  if m.racks.data.len > 0:
    return m.racks.data[0].id
  m.rackCreate("default")

proc rackDestroy*(m: var NilrackModel, id: RackId) =
  m.nodesByRack.del(id)
  m.cablesByRack.del(id)
  discard m.racks.delete(id)
