import std/atomics
import ../types/audio_values

proc initProcessPlanSlot*(slot: var ProcessPlanSlot) =
  slot.current.store(nil, moRelaxed)
  slot.callbackEpoch.store(0'u64, moRelaxed)

proc loadProcessPlan*(slot: var ProcessPlanSlot): ptr ProcessPlan =
  cast[ptr ProcessPlan](slot.current.load(moAcquire))

proc publishProcessPlan*(
    slot: var ProcessPlanSlot, plan: ptr ProcessPlan
): ptr ProcessPlan =
  cast[ptr ProcessPlan](slot.current.exchange(cast[pointer](plan), moAcquireRelease))

proc clearProcessPlan*(slot: var ProcessPlanSlot): ptr ProcessPlan =
  slot.publishProcessPlan(nil)

proc advanceCallbackEpoch*(slot: var ProcessPlanSlot): uint64 =
  slot.callbackEpoch.fetchAdd(1'u64, moRelease) + 1'u64

proc loadCallbackEpoch*(slot: var ProcessPlanSlot): uint64 =
  slot.callbackEpoch.load(moAcquire)

proc initProcessPlanRetireQueue*(queue: var ProcessPlanRetireQueue) =
  queue.count = 0
  queue.overflowed = false

proc enqueueRetiredProcessPlan*(
    queue: var ProcessPlanRetireQueue, slot: var ProcessPlanSlot, plan: ptr ProcessPlan
): bool =
  if plan.isNil:
    return true
  if queue.count >= MaxRetiredProcessPlans.uint32:
    queue.overflowed = true
    return false
  queue.entries[queue.count.int] =
    RetiredProcessPlan(plan: plan, safeAfterEpoch: slot.loadCallbackEpoch() + 1'u64)
  inc queue.count
  true

proc removeRetiredAt(queue: var ProcessPlanRetireQueue, index: int): ptr ProcessPlan =
  result = queue.entries[index].plan
  let last = queue.count.int - 1
  for i in index ..< last:
    queue.entries[i] = queue.entries[i + 1]
  queue.entries[last] = RetiredProcessPlan()
  dec queue.count

proc popReadyRetiredProcessPlan*(
    queue: var ProcessPlanRetireQueue, slot: var ProcessPlanSlot
): ptr ProcessPlan =
  let epoch = slot.loadCallbackEpoch()
  for i in 0 ..< queue.count.int:
    if epoch >= queue.entries[i].safeAfterEpoch:
      return queue.removeRetiredAt(i)
  nil

proc popRetiredProcessPlanImmediate*(
    queue: var ProcessPlanRetireQueue
): ptr ProcessPlan =
  if queue.count == 0:
    return nil
  queue.removeRetiredAt(0)
