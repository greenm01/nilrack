import audio_values
import core

type
  PluginRuntimeStatus* = enum
    prsOk
    prsBypass
    prsFailed

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
