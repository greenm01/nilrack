import std/atomics
import core

const
  MaxProcessPlanNodes* = 64
  MaxProcessPlanEntries* = 64
  MaxProcessPlanPluginTargets* = 64
  MaxProcessPlanParamTargets* = 256
  MaxProcessPlanEventPortTargets* = 128
  MaxRetiredProcessPlans* = 64
  MaxPluginParamEvents* = 256

type
  AudioIoMode* = enum
    aimBypass
    aimMonoLeftToStereo
    aimStereo

  AudioDiagnosticKind* = enum
    adkQueueFull
    adkEventBufferFull
    adkMidiBufferFull
    adkFeedbackDropped
    adkStaleEvent
    adkXRun
    adkPluginProcessError
    adkTopologyRefreshRequested
    adkRetireQueueOverflow
    adkReconfigRequested

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

  ProcessParamTarget* = object
    pluginId*: PluginId
    paramId*: ParamId

  ProcessPlan* = object
    generation*: uint64
    nodeCount*: uint32
    nodes*: array[MaxProcessPlanNodes, NodeId]
    entryCount*: uint32
    entries*: array[MaxProcessPlanEntries, AudioProcessEntry]
    pluginTargetCount*: uint32
    pluginTargets*: array[MaxProcessPlanPluginTargets, PluginId]
    paramTargetCount*: uint32
    paramTargets*: array[MaxProcessPlanParamTargets, ProcessParamTarget]
    eventPortTargetCount*: uint32
    eventPortTargets*: array[MaxProcessPlanEventPortTargets, PortId]
    capacityExceeded*: bool

  ProcessPlanSlot* = object
    current*: Atomic[pointer]
    callbackEpoch*: Atomic[uint64]

  RetiredProcessPlan* = object
    plan*: ptr ProcessPlan
    safeAfterEpoch*: uint64

  ProcessPlanRetireQueue* = object
    count*: uint32
    entries*: array[MaxRetiredProcessPlans, RetiredProcessPlan]
    overflowed*: bool

  AudioCallbackDiagnostics* = object
    generation*: Atomic[uint32]
    counters*: array[AudioDiagnosticKind, Atomic[uint32]]

  AudioCallbackDiagnosticsSnapshot* = object
    generation*: uint32
    counters*: array[AudioDiagnosticKind, uint32]

  AudioReconfigurationRequest* = object
    generation*: uint32
    sampleRate*: uint32
    bufferSize*: uint32

  AudioReconfigurationState* = object
    generation*: Atomic[uint32]
    sampleRate*: Atomic[uint32]
    bufferSize*: Atomic[uint32]

  PluginParamEventKind* = enum
    ppekValue
    ppekGestureBegin
    ppekGestureEnd

  PluginParamEvent* = object
    kind*: PluginParamEventKind
    pluginId*: PluginId
    paramId*: ParamId
    normalizedValue*: float64
    sampleOffset*: uint32

  RtQueue*[T; N: static int] = object
    data*: array[N, T]
    head*: Atomic[int]
    tail*: Atomic[int]

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
    diagnostics*: AudioCallbackDiagnostics
    reconfiguration*: AudioReconfigurationState
    paramEvents*: RtQueue[PluginParamEvent, MaxPluginParamEvents]

  MeterSnapshot* = object
    levels*: array[4, float32]
