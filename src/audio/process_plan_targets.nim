import ../types/[audio_values, core]
import ../key_ops

proc hasLivePluginTarget*(plan: ptr ProcessPlan, pluginId: PluginId): bool =
  if plan.isNil or pluginId == NullPluginId:
    return false
  for i in 0 ..< plan.pluginTargetCount.int:
    if plan.pluginTargets[i] == pluginId:
      return true
  false

proc hasParamTarget*(
    plan: ptr ProcessPlan, pluginId: PluginId, paramId: ParamId
): bool =
  if plan.isNil or pluginId == NullPluginId or paramId == NullParamId:
    return false
  if not plan.hasLivePluginTarget(pluginId):
    return false
  for i in 0 ..< plan.paramTargetCount.int:
    let target = plan.paramTargets[i]
    if target.pluginId == pluginId and target.paramId == paramId:
      return true
  false

proc hasEventPortTarget*(plan: ptr ProcessPlan, portId: PortId): bool =
  if plan.isNil or portId == NullPortId:
    return false
  for i in 0 ..< plan.eventPortTargetCount.int:
    if plan.eventPortTargets[i] == portId:
      return true
  false
