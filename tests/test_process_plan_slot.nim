import std/unittest

import ../src/types/audio_values

suite "process plan slot":
  test "publishes loads and clears process plan pointers":
    var slot: ProcessPlanSlot
    slot.initProcessPlanSlot()

    var planA: ProcessPlan
    var planB: ProcessPlan

    check slot.loadProcessPlan().isNil
    check slot.loadCallbackEpoch() == 0

    check slot.publishProcessPlan(addr planA).isNil
    check slot.loadProcessPlan() == addr planA

    check slot.publishProcessPlan(addr planB) == addr planA
    check slot.loadProcessPlan() == addr planB

    check slot.clearProcessPlan() == addr planB
    check slot.loadProcessPlan().isNil

  test "advances callback epoch monotonically":
    var slot: ProcessPlanSlot
    slot.initProcessPlanSlot()

    check slot.advanceCallbackEpoch() == 1
    check slot.loadCallbackEpoch() == 1
    check slot.advanceCallbackEpoch() == 2
    check slot.loadCallbackEpoch() == 2
