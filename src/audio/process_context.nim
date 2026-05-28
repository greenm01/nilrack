import ../types/audio_values
import ../types/core

type
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
