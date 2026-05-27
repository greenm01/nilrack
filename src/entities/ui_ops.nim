import std/[options, tables]
import ../types/core
import ../state/[entity_manager, id_gen, model]

proc inputTargetCreate*(
    m: var NilrackModel, nodeId: NodeId, x, y, w, h: float32
): InputTargetId =
  let id = m.counters.generateInputTargetId()
  m.inputTargets.insert(InputTargetData(id: id, nodeId: nodeId, x: x, y: y, w: w, h: h))
  m.inputTargetByNode[nodeId] = id
  id

proc pluginUiCreate*(m: var NilrackModel, pluginId: PluginId): PluginUiId =
  let id = m.counters.generatePluginUiId()
  m.pluginUis.insert(PluginUiData(id: id, pluginId: pluginId))
  m.uiByPlugin[pluginId] = id
  id

proc pluginUiDestroy*(m: var NilrackModel, id: PluginUiId) =
  let ui = m.pluginUis.entity(id)
  if ui.isSome:
    m.uiByPlugin.del(ui.get.pluginId)
  discard m.pluginUis.delete(id)
