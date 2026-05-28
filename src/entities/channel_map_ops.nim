import std/[options, tables]

import ../types/core
import ../state/[entity_manager, id_gen, model]

proc channelMapCreate*(
    m: var NilrackModel, rackId: RackId, entries: openArray[ChannelMapEntry]
): ChannelMapId =
  let id = m.counters.generateChannelMapId()
  m.channelMaps.insert(ChannelMapData(id: id, rackId: rackId, entries: @entries))
  m.channelMapsByRack.mgetOrPut(rackId, @[]).add(id)
  id

proc channelMapDestroy*(m: var NilrackModel, id: ChannelMapId) =
  let channelMap = m.channelMaps.entity(id)
  if channelMap.isSome:
    let rack = channelMap.get.rackId
    let channelMaps = m.channelMapsByRack.getOrDefault(rack, @[])
    m.channelMapsByRack[rack] = block:
      var s: seq[ChannelMapId]
      for candidate in channelMaps:
        if candidate != id:
          s.add(candidate)
      s
    for cable in m.cables.data.mitems:
      if cable.channelMapId == id:
        cable.channelMapId = NullChannelMapId
        if cable.routePolicy == crChannelMap:
          cable.routePolicy = crAuto
  discard m.channelMaps.delete(id)
