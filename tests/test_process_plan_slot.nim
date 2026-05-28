import std/unittest

import ../src/audio/process_plan_store
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

  test "retire queue pops plans after safe epoch":
    var slot: ProcessPlanSlot
    slot.initProcessPlanSlot()
    var queue: ProcessPlanRetireQueue
    queue.initProcessPlanRetireQueue()
    var planA: ProcessPlan
    var planB: ProcessPlan

    check queue.enqueueRetiredProcessPlan(slot, addr planA)
    check queue.enqueueRetiredProcessPlan(slot, addr planB)
    check queue.count == 2
    check queue.entries[0].safeAfterEpoch == 1
    check queue.popReadyRetiredProcessPlan(slot).isNil

    discard slot.advanceCallbackEpoch()
    check queue.popReadyRetiredProcessPlan(slot) == addr planA
    check queue.count == 1
    check queue.popReadyRetiredProcessPlan(slot) == addr planB
    check queue.count == 0
    check queue.popReadyRetiredProcessPlan(slot).isNil

  test "retire queue drains immediately after backend stop":
    var slot: ProcessPlanSlot
    slot.initProcessPlanSlot()
    var queue: ProcessPlanRetireQueue
    queue.initProcessPlanRetireQueue()
    var plan: ProcessPlan

    check queue.enqueueRetiredProcessPlan(slot, addr plan)
    check queue.popRetiredProcessPlanImmediate() == addr plan
    check queue.count == 0

  test "retire queue reports overflow":
    var slot: ProcessPlanSlot
    slot.initProcessPlanSlot()
    var queue: ProcessPlanRetireQueue
    queue.initProcessPlanRetireQueue()
    var plans: array[MaxRetiredProcessPlans + 1, ProcessPlan]

    for i in 0 ..< MaxRetiredProcessPlans:
      check queue.enqueueRetiredProcessPlan(slot, addr plans[i])

    check not queue.enqueueRetiredProcessPlan(slot, addr plans[MaxRetiredProcessPlans])
    check queue.overflowed
    check queue.count == MaxRetiredProcessPlans.uint32
