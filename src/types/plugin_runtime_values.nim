import std/atomics
import core
import audio_values

const
  MaxPluginEventThreadEvents* = 128
  MaxPluginRuntimes* = 64

type
  PluginRuntimeStatus* = enum
    prsOk
    prsBypass
    prsFailed

  PluginHostCallbackFlag* = enum
    phcfRestart
    phcfProcess
    phcfCallback
    phcfLog
    phcfParam
    phcfFd
    phcfTimer
    phcfStateDirty

  PluginHostCallbackFlags* = object
    bits*: Atomic[uint32]

  PluginHostCallbackSnapshot* = object
    flags*: set[PluginHostCallbackFlag]

  PluginEventThreadEventKind* = enum
    peteClapFdRegister
    peteClapFdModify
    peteClapFdUnregister
    peteClapTimerRegister
    peteClapTimerUnregister

  PluginEventThreadEvent* = object
    kind*: PluginEventThreadEventKind
    pluginId*: PluginId
    fd*: int32
    fdFlags*: uint32
    timerId*: uint32
    periodMs*: uint32

  PluginEventThreadQueue* = RtQueue[PluginEventThreadEvent, MaxPluginEventThreadEvents]

  PluginRuntimeActivateProc* = proc(
    runtime: pointer, sampleRate: float64, minFrames, maxFrames: uint32
  ): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].}

  PluginRuntimeSimpleProc* =
    proc(runtime: pointer): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].}

  PluginTransportSnapshot* = object
    playing*: bool
    frame*: uint64
    tempo*: float64

  PluginEventContext* = object
    paramEvents*: ptr UncheckedArray[PluginParamEvent]
    paramEventCount*: uint32
    midiEvents*: ptr UncheckedArray[PluginMidiEvent]
    midiEventCount*: uint32
    transport*: ptr PluginTransportSnapshot

  PluginAudioBus* = object
    portId*: PortId
    channels*: ptr UncheckedArray[pointer]
    channelCount*: uint32

  ProcessContext* = object
    frames*: uint32
    audioInputs*: ptr UncheckedArray[PluginAudioBus]
    audioInputBusCount*: uint32
    audioOutputs*: ptr UncheckedArray[PluginAudioBus]
    audioOutputBusCount*: uint32
    events*: PluginEventContext

  PluginRuntimeProcessProc* = proc(
    runtime: pointer, context: ptr ProcessContext
  ): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].}

  PluginRuntimeDestroyProc* = proc(runtime: pointer) {.nimcall, gcsafe, raises: [].}

  PluginRuntimeOps* = object
    activate*: PluginRuntimeActivateProc
    deactivate*: PluginRuntimeSimpleProc
    startProcessing*: PluginRuntimeSimpleProc
    stopProcessing*: PluginRuntimeSimpleProc
    process*: PluginRuntimeProcessProc
    destroy*: PluginRuntimeDestroyProc

  PluginRuntimeRef* = object
    pluginId*: PluginId
    runtime*: pointer
    ops*: ptr PluginRuntimeOps
    processBlock*: AudioBlockProcessProc

  PluginRuntimeStore* = object
    count*: uint32
    runtimes*: array[MaxPluginRuntimes, PluginRuntimeRef]
    capacityExceeded*: bool
