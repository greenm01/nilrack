import std/[options, tables]
import ../types/core
import ../state/[entity_manager, id_gen, model]

proc pluginAttachToNode*(
    m: var NilrackModel,
    nodeId: NodeId,
    api: PluginApi,
    path, uri, displayName: string,
    vendor: string = "",
    version: string = "",
    hasState: bool = false,
): PluginId =
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
    m.pluginByNode.del(plugin.get.nodeId)
    m.nodeByPlugin.del(id)
    m.uiByPlugin.del(id)
  discard m.plugins.delete(id)
