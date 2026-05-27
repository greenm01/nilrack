import std/[options, tables]
import ../types/core
import model
import entity_manager

proc rackData*(m: NilrackModel, id: RackId): Option[RackData] =
  m.racks.entity(id)

proc nodeData*(m: NilrackModel, id: NodeId): Option[NodeData] =
  m.nodes.entity(id)

proc cableData*(m: NilrackModel, id: CableId): Option[CableData] =
  m.cables.entity(id)

proc portData*(m: NilrackModel, id: PortId): Option[PortData] =
  m.ports.entity(id)

proc paramData*(m: NilrackModel, id: ParamId): Option[ParamData] =
  m.params.entity(id)

proc pluginData*(m: NilrackModel, id: PluginId): Option[PluginData] =
  m.plugins.entity(id)

proc pluginForNode*(m: NilrackModel, id: NodeId): Option[PluginId] =
  if m.pluginByNode.hasKey(id):
    some(m.pluginByNode[id])
  else:
    none(PluginId)

proc portsForNode*(m: NilrackModel, id: NodeId): seq[PortId] =
  m.portsByNode.getOrDefault(id, @[])

proc paramsForNode*(m: NilrackModel, id: NodeId): seq[ParamId] =
  m.paramsByNode.getOrDefault(id, @[])

proc inputTargetAt*(m: NilrackModel, x, y: float32): Option[InputTargetId] =
  for entry in m.inputTargets.data:
    if x >= entry.x and x < entry.x + entry.w and y >= entry.y and y < entry.y + entry.h:
      return some(entry.id)
  none(InputTargetId)

proc canConnect*(m: NilrackModel, src, dst: PortId): bool =
  let srcPort = m.ports.entity(src)
  let dstPort = m.ports.entity(dst)
  if srcPort.isNone or dstPort.isNone:
    return false
  srcPort.get.kind == dstPort.get.kind and srcPort.get.direction == pdOut and
    dstPort.get.direction == pdIn
