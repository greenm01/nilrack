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

proc nodeSetBypassed*(m: var NilrackModel, id: NodeId, bypassed: bool) =
  if m.nodes.contains(id):
    m.nodes.mEntity(id).bypassed = bypassed

proc nodeToggleBypass*(m: var NilrackModel, id: NodeId) =
  if m.nodes.contains(id):
    m.nodes.mEntity(id).bypassed = not m.nodes.mEntity(id).bypassed
