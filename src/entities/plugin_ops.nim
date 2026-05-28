import std/[options, tables]
import ../types/core
import ../state/[entity_manager, id_gen, model]

proc pluginDetach*(m: var NilrackModel, id: PluginId)

proc pluginAttachToNode*(
    m: var NilrackModel,
    nodeId: NodeId,
    api: PluginApi,
    path, uri, displayName: string,
    vendor: string = "",
    version: string = "",
    hasState: bool = false,
): PluginId =
  if m.pluginByNode.hasKey(nodeId):
    m.pluginDetach(m.pluginByNode[nodeId])
  let id = m.counters.generatePluginId()
  m.plugins.insert(
    PluginData(
      id: id,
      nodeId: nodeId,
      api: api,
      path: path,
      uri: uri,
      displayName: displayName,
      vendor: vendor,
      version: version,
      hasState: hasState,
    )
  )
  m.pluginByNode[nodeId] = id
  m.nodeByPlugin[id] = nodeId
  id

proc pluginDetach*(m: var NilrackModel, id: PluginId) =
  let plugin = m.plugins.entity(id)
  if plugin.isSome:
    let nodeId = plugin.get.nodeId
    var cablesToDelete: seq[CableId]
    for cable in m.cables.data:
      for portId in m.portsByNode.getOrDefault(nodeId, @[]):
        if cable.srcPort == portId or cable.dstPort == portId:
          cablesToDelete.add(cable.id)
          break

    for cableId in cablesToDelete:
      let cable = m.cables.entity(cableId)
      if cable.isSome:
        m.cablesByRack[cable.get.rackId] = block:
          var s: seq[CableId]
          for candidate in m.cablesByRack.getOrDefault(cable.get.rackId, @[]):
            if candidate != cableId:
              s.add(candidate)
          s
      discard m.cables.delete(cableId)

    for portId in m.portsByNode.getOrDefault(plugin.get.nodeId, @[]):
      var keysToDelete: seq[ExternalPortKey]
      for key, value in m.portByExternalKey.pairs:
        if value == portId:
          keysToDelete.add(key)
      for key in keysToDelete:
        m.portByExternalKey.del(key)
      discard m.ports.delete(portId)
    m.portsByNode[nodeId] = @[]

    for paramId in m.paramsByNode.getOrDefault(nodeId, @[]):
      var keysToDelete: seq[ExternalParamKey]
      for key, value in m.paramByExternalKey.pairs:
        if value == paramId:
          keysToDelete.add(key)
      for key in keysToDelete:
        m.paramByExternalKey.del(key)
      discard m.params.delete(paramId)
    m.paramsByNode[nodeId] = @[]

    m.pluginByNode.del(nodeId)
    m.nodeByPlugin.del(id)
    let uiId = m.uiByPlugin.getOrDefault(id, NullPluginUiId)
    if uiId != NullPluginUiId:
      discard m.pluginUis.delete(uiId)
    m.uiByPlugin.del(id)
  discard m.plugins.delete(id)

proc pluginSetStateRef*(m: var NilrackModel, id: PluginId, stateRef: StateBlobRef) =
  if not m.plugins.contains(id):
    return
  m.plugins.mEntity(id).stateRef = stateRef
