import std/[options, tables]
import ../types/core
import ../state/[entity_manager, id_gen, model]

proc cableCreate*(m: var NilrackModel, rackId: RackId, src, dst: PortId): CableId =
  let srcPort = m.ports.entity(src)
  let kind = if srcPort.isSome: srcPort.get.kind else: pkAudio
  let id = m.counters.generateCableId()
  m.cables.insert(
    CableData(id: id, rackId: rackId, srcPort: src, dstPort: dst, kind: kind)
  )
  m.cablesByRack.mgetOrPut(rackId, @[]).add(id)
  id

proc cableDestroy*(m: var NilrackModel, id: CableId) =
  let cable = m.cables.entity(id)
  if cable.isSome:
    let rack = cable.get.rackId
    let cables = m.cablesByRack.getOrDefault(rack, @[])
    m.cablesByRack[rack] = block:
      var s: seq[CableId]
      for c in cables:
        if c != id:
          s.add(c)
      s
  discard m.cables.delete(id)

proc cableSetRoutePolicy*(
    m: var NilrackModel, id: CableId, routePolicy: CableRoutePolicy
) =
  if m.cables.contains(id):
    m.cables.mEntity(id).routePolicy = routePolicy

proc cableSetChannelMap*(m: var NilrackModel, id: CableId, channelMapId: ChannelMapId) =
  if not m.cables.contains(id):
    return
  m.cables.mEntity(id).channelMapId = channelMapId
  m.cables.mEntity(id).routePolicy =
    if channelMapId == NullChannelMapId: crAuto else: crChannelMap
