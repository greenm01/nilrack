import std/unittest

import ../src/systems/effect_queue
import ../src/types/[core, effect_values, ui_values]

suite "effect queue":
  test "routes dirty effects through bounded queue":
    var queue: EffectQueue
    var effect: Effect

    check queue.enqueueGraphDirty(RackId(1))
    check queue.enqueueProcessPlanDirty(RackId(1))
    check queue.enqueueTopologyRefresh(PluginId(2))
    check queue.enqueueDiagnosticsDirty()
    check queue.enqueueStateDirty(PluginId(3))

    check queue.count == 5
    check queue.popEffect(effect)
    check effect.kind == ekGraphDirty
    check effect.rackId == RackId(1)
    check queue.popEffect(effect)
    check effect.kind == ekProcessPlanDirty
    check queue.popEffect(effect)
    check effect.kind == ekTopologyRefresh
    check effect.pluginId == PluginId(2)

  test "routes messages to dirty effects":
    var queue: EffectQueue
    var effect: Effect

    check queue.routeMsgEffects(Msg(kind: msgPluginLoaded))
    check queue.count == 2
    check queue.popEffect(effect)
    check effect.kind == ekGraphDirty
    check queue.popEffect(effect)
    check effect.kind == ekProcessPlanDirty

    check queue.routeMsgEffects(Msg(kind: msgAudioSnapshot))
    check queue.popEffect(effect)
    check effect.kind == ekDiagnosticsDirty

  test "effect queue remains bounded":
    var queue: EffectQueue

    for i in 0 ..< MaxEffectQueueEntries:
      check queue.enqueueDiagnosticsDirty()

    check not queue.enqueueDiagnosticsDirty()
    check queue.overflowed
    check queue.count == MaxEffectQueueEntries.uint32
