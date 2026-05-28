import ../types/[core, effect_values, ui_values]

proc pushEffect*(queue: var EffectQueue, effect: Effect): bool =
  if queue.count >= MaxEffectQueueEntries.uint32:
    queue.overflowed = true
    return false
  queue.entries[queue.count.int] = effect
  inc queue.count
  true

proc popEffect*(queue: var EffectQueue, effect: var Effect): bool =
  if queue.count == 0:
    return false
  effect = queue.entries[0]
  let last = queue.count.int - 1
  for i in 0 ..< last:
    queue.entries[i] = queue.entries[i + 1]
  queue.entries[last] = Effect()
  dec queue.count
  true

proc enqueueGraphDirty*(queue: var EffectQueue, rackId: RackId): bool =
  queue.pushEffect(Effect(kind: ekGraphDirty, rackId: rackId))

proc enqueueProcessPlanDirty*(queue: var EffectQueue, rackId: RackId): bool =
  queue.pushEffect(Effect(kind: ekProcessPlanDirty, rackId: rackId))

proc enqueueTopologyRefresh*(queue: var EffectQueue, pluginId: PluginId): bool =
  queue.pushEffect(Effect(kind: ekTopologyRefresh, pluginId: pluginId))

proc enqueueDiagnosticsDirty*(queue: var EffectQueue): bool =
  queue.pushEffect(Effect(kind: ekDiagnosticsDirty))

proc enqueueStateDirty*(queue: var EffectQueue, pluginId: PluginId): bool =
  queue.pushEffect(Effect(kind: ekStateDirty, pluginId: pluginId))

proc routeMsgEffects*(queue: var EffectQueue, msg: Msg): bool =
  case msg.kind
  of msgPluginLoaded, msgPluginUnloaded:
    result = queue.enqueueGraphDirty(NullRackId)
    result = queue.enqueueProcessPlanDirty(NullRackId) and result
  of msgAudioSnapshot:
    result = queue.enqueueDiagnosticsDirty()
  else:
    result = false
