import std/[options, tables]
import ../types/core
import ../state/[entity_manager, id_gen, model]

proc nodeCreate*(
    m: var NilrackModel, rackId: RackId, kind: NodeKind, name: string
): NodeId =
  let id = m.counters.generateNodeId()
  m.nodes.insert(NodeData(id: id, rackId: rackId, kind: kind, name: name))
  m.nodesByRack.mgetOrPut(rackId, @[]).add(id)
  m.portsByNode[id] = @[]
  m.paramsByNode[id] = @[]
  id

proc nodeDestroy*(m: var NilrackModel, id: NodeId) =
  var cablesToDelete: seq[CableId]
  for cable in m.cables.data:
    if cable.srcPort != NullPortId and cable.dstPort != NullPortId:
      let src = m.ports.entity(cable.srcPort)
      let dst = m.ports.entity(cable.dstPort)
      if (src.isSome and src.get.nodeId == id) or (dst.isSome and dst.get.nodeId == id):
        cablesToDelete.add(cable.id)

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

  var pluginsToDelete: seq[PluginId]
  for plugin in m.plugins.data:
    if plugin.nodeId == id:
      pluginsToDelete.add(plugin.id)

  for pluginId in pluginsToDelete:
    let uiId = m.uiByPlugin.getOrDefault(pluginId, NullPluginUiId)
    if uiId != NullPluginUiId:
      discard m.pluginUis.delete(uiId)
    m.pluginByNode.del(id)
    m.nodeByPlugin.del(pluginId)
    m.uiByPlugin.del(pluginId)
    discard m.plugins.delete(pluginId)

  for portId in m.portsByNode.getOrDefault(id, @[]):
    var keysToDelete: seq[ExternalPortKey]
    for key, value in m.portByExternalKey.pairs:
      if value == portId:
        keysToDelete.add(key)
    for key in keysToDelete:
      m.portByExternalKey.del(key)
    discard m.ports.delete(portId)

  for paramId in m.paramsByNode.getOrDefault(id, @[]):
    var keysToDelete: seq[ExternalParamKey]
    for key, value in m.paramByExternalKey.pairs:
      if value == paramId:
        keysToDelete.add(key)
    for key in keysToDelete:
      m.paramByExternalKey.del(key)
    discard m.params.delete(paramId)

  let inputTargetId = m.inputTargetByNode.getOrDefault(id, NullInputTargetId)
  if inputTargetId != NullInputTargetId:
    discard m.inputTargets.delete(inputTargetId)
  m.portsByNode.del(id)
  m.paramsByNode.del(id)
  m.inputTargetByNode.del(id)
  let node = m.nodes.entity(id)
  if node.isSome:
    let rack = node.get.rackId
    let nodes = m.nodesByRack.getOrDefault(rack, @[])
    m.nodesByRack[rack] = block:
      var s: seq[NodeId]
      for n in nodes:
        if n != id:
          s.add(n)
      s
  discard m.nodes.delete(id)

proc nodeMove*(m: var NilrackModel, id: NodeId, x, y: float32) =
  if m.nodes.contains(id):
    m.nodes.mEntity(id).x = x
    m.nodes.mEntity(id).y = y

proc nodeResize*(m: var NilrackModel, id: NodeId, w, h: float32) =
  if m.nodes.contains(id):
    m.nodes.mEntity(id).w = w
    m.nodes.mEntity(id).h = h

proc nodeSetBypassed*(m: var NilrackModel, id: NodeId, bypassed: bool) =
  if m.nodes.contains(id):
    m.nodes.mEntity(id).bypassed = bypassed

proc nodeToggleBypass*(m: var NilrackModel, id: NodeId) =
  if m.nodes.contains(id):
    m.nodes.mEntity(id).bypassed = not m.nodes.mEntity(id).bypassed
