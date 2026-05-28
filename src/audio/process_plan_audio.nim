import process_context
import ../plugins/plugin_runtime_api
import ../types/[audio_values, core]

proc copyPassthrough(
    in1, in2, out1, out2: ptr UncheckedArray[float32], nframes: uint32
) =
  copyMem(out1, in1, nframes.int * sizeof(float32))
  copyMem(out2, in2, nframes.int * sizeof(float32))

proc tryProcessPlan*(
    plan: ptr ProcessPlan, in1, in2, out1, out2: pointer, nframes: uint32
): bool =
  if plan.isNil or plan.entryCount == 0:
    return false

  let entry = addr plan.entries[0]
  let ops = cast[ptr PluginRuntimeOps](entry.ops)
  if not entry.active or entry.ioMode == aimBypass or ops.isNil or ops.process.isNil:
    return false

  let channels =
    case entry.ioMode
    of aimMonoLeftToStereo: 1'u32
    of aimStereo: 2'u32
    of aimBypass: 0'u32
  if channels == 0:
    return false

  var inputChannels = [in1, in2]
  var outputChannels = [out1, out2]
  var inputBuses = [
    PluginAudioBus(
      portId: NullPortId,
      channels: cast[ptr UncheckedArray[pointer]](addr inputChannels[0]),
      channelCount: channels,
    )
  ]
  var outputBuses = [
    PluginAudioBus(
      portId: NullPortId,
      channels: cast[ptr UncheckedArray[pointer]](addr outputChannels[0]),
      channelCount: channels,
    )
  ]
  var context = ProcessContext(
    frames: nframes,
    audioInputs: cast[ptr UncheckedArray[PluginAudioBus]](addr inputBuses[0]),
    audioInputBusCount: inputBuses.len.uint32,
    audioOutputs: cast[ptr UncheckedArray[PluginAudioBus]](addr outputBuses[0]),
    audioOutputBusCount: outputBuses.len.uint32,
  )

  let status = ops.process(entry.runtime, addr context)
  if status != prsOk:
    return false
  if entry.ioMode == aimMonoLeftToStereo:
    copyMem(out2, out1, nframes.int * sizeof(float32))
  true

proc processAudioBlock*(
    plan: ptr ProcessPlan, in1, in2, out1, out2: pointer, nframes: uint32
): bool =
  result = tryProcessPlan(plan, in1, in2, out1, out2, nframes)
  if not result:
    copyPassthrough(
      cast[ptr UncheckedArray[float32]](in1),
      cast[ptr UncheckedArray[float32]](in2),
      cast[ptr UncheckedArray[float32]](out1),
      cast[ptr UncheckedArray[float32]](out2),
      nframes,
    )
