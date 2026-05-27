import std/tables
import ../types/core
import ../state/[entity_manager, id_gen, model]

proc renderSurfaceCreate*(m: var NilrackModel): RenderSurfaceId =
  let id = m.counters.generateRenderSurfaceId()
  m.renderSurfaces.insert(RenderSurfaceData(id: id))
  id

proc portCreate*(
    m: var NilrackModel,
    nodeId: NodeId,
    kind: PortKind,
    direction: PortDirection,
    channelIndex: uint32,
    name: string,
): PortId =
  let id = m.counters.generatePortId()
  m.ports.insert(
    PortData(
      id: id,
      nodeId: nodeId,
      kind: kind,
      direction: direction,
      channelIndex: channelIndex,
      name: name,
    )
  )
  m.portsByNode.mgetOrPut(nodeId, @[]).add(id)
  id
