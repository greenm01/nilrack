import ../types/[audio_values, core]
import ../key_ops
import audio_feedback
import callback_diagnostics
import process_plan_targets
import rt_queue

proc hasGestureTarget(
    tracker: PluginParamGestureTracker, pluginId: PluginId, paramId: ParamId
): bool =
  for i in 0 ..< tracker.count.int:
    let target = tracker.targets[i]
    if target.pluginId == pluginId and target.paramId == paramId:
      return true
  false

proc addGestureTarget(
    tracker: var PluginParamGestureTracker, pluginId: PluginId, paramId: ParamId
): bool =
  if tracker.hasGestureTarget(pluginId, paramId):
    return true
  if tracker.count >= MaxPluginParamGestures.uint32:
    return false
  tracker.targets[tracker.count.int] =
    ProcessParamTarget(pluginId: pluginId, paramId: paramId)
  inc tracker.count
  true

proc removeGestureTarget(
    tracker: var PluginParamGestureTracker, pluginId: PluginId, paramId: ParamId
): bool =
  for i in 0 ..< tracker.count.int:
    let target = tracker.targets[i]
    if target.pluginId == pluginId and target.paramId == paramId:
      let last = tracker.count.int - 1
      tracker.targets[i] = tracker.targets[last]
      tracker.targets[last] = ProcessParamTarget()
      dec tracker.count
      return true
  false

proc enqueuePluginParamEvent*(backend: var JackBackend, event: PluginParamEvent): bool =
  result = backend.paramEvents.push(event)
  if not result:
    backend.diagnostics.incrementAudioDiagnostic(adkQueueFull)
    backend.feedback.markAudioFeedback(affQueueOverflow)

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

proc enqueuePluginParamGestureBegin*(
    backend: var JackBackend, pluginId: PluginId, paramId: ParamId
): bool =
  if backend.paramGestures.hasGestureTarget(pluginId, paramId):
    return true
  if backend.paramGestures.count >= MaxPluginParamGestures.uint32:
    backend.diagnostics.incrementAudioDiagnostic(adkQueueFull)
    return false
  result = backend.enqueuePluginParamEvent(
    PluginParamEvent(kind: ppekGestureBegin, pluginId: pluginId, paramId: paramId)
  )
  if result:
    discard backend.paramGestures.addGestureTarget(pluginId, paramId)

proc enqueuePluginParamGestureEnd*(
    backend: var JackBackend, pluginId: PluginId, paramId: ParamId
): bool =
  let wasActive = backend.paramGestures.removeGestureTarget(pluginId, paramId)
  if not wasActive:
    return true
  backend.enqueuePluginParamEvent(
    PluginParamEvent(kind: ppekGestureEnd, pluginId: pluginId, paramId: paramId)
  )

proc hasActivePluginParamGesture*(
    backend: JackBackend, pluginId: PluginId, paramId: ParamId
): bool =
  backend.paramGestures.hasGestureTarget(pluginId, paramId)

proc popValidatedPluginParamEvent*(
    backend: var JackBackend, plan: ptr ProcessPlan, event: var PluginParamEvent
): bool =
  var candidate: PluginParamEvent
  while backend.paramEvents.pop(candidate):
    if plan.hasParamTarget(candidate.pluginId, candidate.paramId):
      event = candidate
      return true
    backend.diagnostics.incrementAudioDiagnostic(adkStaleEvent)
    backend.feedback.markAudioFeedback(affStaleEvent)
  false
