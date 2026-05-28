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
    externalIndex: uint32 = 0,
    externalId: uint32 = 0,
    channelCount: uint32 = 1,
    isMain: bool = false,
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
      externalIndex: externalIndex,
      externalId: externalId,
      channelCount: channelCount,
      isMain: isMain,
    )
  )
  m.portsByNode.mgetOrPut(nodeId, @[]).add(id)
  id

proc portBindExternalKey*(
    m: var NilrackModel, pluginId: PluginId, externalIndex: uint32, portId: PortId
) =
  if portId == NullPortId or pluginId == NullPluginId:
    return
  m.portByExternalKey[ExternalPortKey(pluginId: pluginId, index: externalIndex)] =
    portId
