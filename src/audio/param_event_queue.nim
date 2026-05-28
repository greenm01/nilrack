import ../types/[audio_values, core]
import callback_diagnostics
import process_plan_targets
import rt_queue

proc enqueuePluginParamEvent*(backend: var JackBackend, event: PluginParamEvent): bool =
  result = backend.paramEvents.push(event)
  if not result:
    backend.diagnostics.incrementAudioDiagnostic(adkQueueFull)

proc enqueuePluginParamValue*(
    backend: var JackBackend,
    pluginId: PluginId,
    paramId: ParamId,
    normalizedValue: float64,
): bool =
  backend.enqueuePluginParamEvent(
    PluginParamEvent(
      kind: ppekValue,
      pluginId: pluginId,
      paramId: paramId,
      normalizedValue: normalizedValue,
    )
  )

proc popValidatedPluginParamEvent*(
    backend: var JackBackend, plan: ptr ProcessPlan, event: var PluginParamEvent
): bool =
  var candidate: PluginParamEvent
  while backend.paramEvents.pop(candidate):
    if plan.hasParamTarget(candidate.pluginId, candidate.paramId):
      event = candidate
      return true
    backend.diagnostics.incrementAudioDiagnostic(adkStaleEvent)
  false
