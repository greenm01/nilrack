import std/[math, options, tables]

import ../types/core
import ../state/[entity_manager, id_gen, model]

proc paramCreate*(
    m: var NilrackModel,
    nodeId: NodeId,
    name: string,
    minVal, maxVal, defaultVal: float64,
    currentVal: float64 = NaN,
    modulePath: string = "",
    externalIndex: uint32 = 0,
    externalId: uint32 = 0,
    displayText: string = "",
    stepped: bool = false,
    hidden: bool = false,
    readonly: bool = false,
    bypass: bool = false,
    automatable: bool = false,
): ParamId =
  let id = m.counters.generateParamId()
  let value = if currentVal.isNaN: defaultVal else: currentVal
  m.params.insert(
    ParamData(
      id: id,
      nodeId: nodeId,
      name: name,
      modulePath: modulePath,
      externalIndex: externalIndex,
      externalId: externalId,
      minVal: minVal,
      maxVal: maxVal,
      defaultVal: defaultVal,
      currentVal: value,
      displayText: displayText,
      stepped: stepped,
      hidden: hidden,
      readonly: readonly,
      bypass: bypass,
      automatable: automatable,
    )
  )
  m.paramsByNode.mgetOrPut(nodeId, @[]).add(id)
  id

proc paramSetNormalized*(m: var NilrackModel, id: ParamId, value: float64) =
  if not m.params.contains(id):
    return
  let snap = m.params.entity(id).get
  m.params.mEntity(id).currentVal = snap.minVal + value * (snap.maxVal - snap.minVal)
