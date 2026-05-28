import std/atomics
import core

const
  MaxProcessPlanNodes* = 64
  MaxProcessPlanEntries* = 64

type
  AudioIoMode* = enum
    aimBypass
    aimMonoLeftToStereo
    aimStereo

  AudioBlockProcessProc* = proc(
    runtime: pointer, in1, in2, out1, out2: pointer, nframes: uint32, mode: AudioIoMode
  ): bool

  AudioProcessEntry* = object
    nodeId*: NodeId
    pluginId*: PluginId
    runtime*: pointer
    processBlock*: AudioBlockProcessProc
    ioMode*: AudioIoMode
    active*: bool

  ProcessPlan* = object
    nodeCount*: uint32
    nodes*: array[MaxProcessPlanNodes, NodeId]
    entryCount*: uint32
    entries*: array[MaxProcessPlanEntries, AudioProcessEntry]
    capacityExceeded*: bool

  ProcessPlanSlot* = object
    current*: Atomic[pointer]
    callbackEpoch*: Atomic[uint64]

  JackClientHandle* = distinct pointer
  JackPortHandle* = distinct pointer

  JackBackend* = object
    client*: JackClientHandle
    inPort1*: JackPortHandle
    inPort2*: JackPortHandle
    outPort1*: JackPortHandle
    outPort2*: JackPortHandle
    sampleRate*: uint32
    bufferSize*: uint32
    planSlot*: ProcessPlanSlot

  MeterSnapshot* = object
    levels*: array[4, float32]

  RtQueue*[T; N: static int] = object
    data*: array[N, T]
    head*: Atomic[int]
    tail*: Atomic[int]

proc addPlanNode*(plan: var ProcessPlan, nodeId: NodeId): bool =
  if plan.nodeCount >= MaxProcessPlanNodes.uint32:
    plan.capacityExceeded = true
    return false
  plan.nodes[plan.nodeCount.int] = nodeId
  inc plan.nodeCount
  true

proc addProcessEntry*(plan: var ProcessPlan, entry: AudioProcessEntry): bool =
  if plan.entryCount >= MaxProcessPlanEntries.uint32:
    plan.capacityExceeded = true
    return false
  plan.entries[plan.entryCount.int] = entry
  inc plan.entryCount
  true

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
