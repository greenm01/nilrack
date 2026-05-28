import std/[strutils, unittest]

import ../src/plugins/plugin_runtime_api
import ../src/key_ops
import ../src/types/[audio_values, core, plugin_runtime_values]

proc okActivate(
    runtime: pointer, sampleRate: float64, minFrames, maxFrames: uint32
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  discard runtime
  discard sampleRate
  discard minFrames
  discard maxFrames
  prsOk

proc okSimple(runtime: pointer): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  discard runtime
  prsOk

proc okProcess(
    runtime: pointer, context: ptr ProcessContext
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  discard runtime
  discard context
  prsOk

proc okDestroy(runtime: pointer) {.nimcall, gcsafe, raises: [].} =
  discard runtime

suite "plugin runtime ops":
  test "ops table accepts fixed no-raise function pointers":
    var ops = PluginRuntimeOps(
      activate: okActivate,
      deactivate: okSimple,
      startProcessing: okSimple,
      stopProcessing: okSimple,
      process: okProcess,
      destroy: okDestroy,
    )
    let runtime = PluginRuntimeRef(pluginId: PluginId(1), runtime: nil, ops: addr ops)
    let runtimeOps = runtime.runtimeOps()

    check runtime.pluginId == PluginId(1)
    check runtimeOps.activate(runtime.runtime, 48000.0, 1, 64) == prsOk
    check runtimeOps.process(runtime.runtime, nil) == prsOk

  test "process context uses pointer slices and counts":
    var paramEvents: array[2, PluginParamEvent]
    var midiEvents: array[1, PluginMidiEvent]
    var inputBuses: array[1, PluginAudioBus]
    var outputBuses: array[1, PluginAudioBus]
    var transport = PluginTransportSnapshot(playing: true, frame: 128, tempo: 120.0)

    let context = ProcessContext(
      frames: 64,
      audioInputs: cast[ptr UncheckedArray[PluginAudioBus]](addr inputBuses[0]),
      audioInputBusCount: inputBuses.len.uint32,
      audioOutputs: cast[ptr UncheckedArray[PluginAudioBus]](addr outputBuses[0]),
      audioOutputBusCount: outputBuses.len.uint32,
      events: PluginEventContext(
        paramEvents: cast[ptr UncheckedArray[PluginParamEvent]](addr paramEvents[0]),
        paramEventCount: paramEvents.len.uint32,
        midiEvents: cast[ptr UncheckedArray[PluginMidiEvent]](addr midiEvents[0]),
        midiEventCount: midiEvents.len.uint32,
        transport: addr transport,
      ),
    )

    check context.frames == 64
    check context.audioInputBusCount == 1
    check context.audioOutputBusCount == 1
    check context.events.paramEventCount == 2
    check context.events.midiEventCount == 1
    check context.events.transport[].playing

  test "runtime ops api stays boundary-safe":
    let source = readFile("src/plugins/plugin_runtime_api.nim")

    for forbidden in ["seq", "ref object", "closure", "raise ", "raise(", "except"]:
      checkpoint "plugin runtime api must not contain " & forbidden
      check not source.contains(forbidden)

    check source.contains("raises: []")
    check source.contains("nimcall")
