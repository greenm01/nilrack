import std/[options, tables]

import ../types/core
import ../state/[entity_manager, id_gen, model]

proc paramCreate*(
    m: var NilrackModel,
    nodeId: NodeId,
    name: string,
    minVal, maxVal, defaultVal: float64,
): ParamId =
  let id = m.counters.generateParamId()
  m.params.insert(
    ParamData(
      id: id,
      nodeId: nodeId,
      name: name,
      minVal: minVal,
      maxVal: maxVal,
      defaultVal: defaultVal,
      currentVal: defaultVal,
    )
  )
  m.paramsByNode.mgetOrPut(nodeId, @[]).add(id)
  id

proc paramSetNormalized*(m: var NilrackModel, id: ParamId, value: float64) =
  if not m.params.contains(id):
    return
  let snap = m.params.entity(id).get
  m.params.mEntity(id).currentVal = snap.minVal + value * (snap.maxVal - snap.minVal)
