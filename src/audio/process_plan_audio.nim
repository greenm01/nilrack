import process_context
import ../plugins/plugin_runtime_api
import ../types/[audio_values, core]

proc copyPassthrough(
    in1, in2, out1, out2: ptr UncheckedArray[float32], nframes: uint32
) =
  copyMem(out1, in1, nframes.int * sizeof(float32))
  copyMem(out2, in2, nframes.int * sizeof(float32))

proc slotPointer(
    slot: ProcessBufferSlot, in1, in2, out1, out2: pointer
): ptr UncheckedArray[float32] =
  case slot.kind
  of pbkHostInput:
    case slot.channel
    of 0:
      cast[ptr UncheckedArray[float32]](in1)
    of 1:
      cast[ptr UncheckedArray[float32]](in2)
    else:
      nil
  of pbkHostOutput:
    case slot.channel
    of 0:
      cast[ptr UncheckedArray[float32]](out1)
    of 1:
      cast[ptr UncheckedArray[float32]](out2)
    else:
      nil

proc opSlotPointer(
    plan: ptr ProcessPlan, index: uint32, in1, in2, out1, out2: pointer
): ptr UncheckedArray[float32] =
  if index >= plan.bufferCount:
    return nil
  slotPointer(plan.buffers[index.int], in1, in2, out1, out2)

proc opBufferIndex(op: ProcessPlanOp, src: bool, channel: uint32): uint32 =
  if src:
    if channel == 0:
      return op.srcBuffer
    return op.srcBuffer2
  if channel == 0:
    return op.dstBuffer
  op.dstBuffer2

proc clearBuffer(dst: ptr UncheckedArray[float32], nframes: uint32) =
  zeroMem(dst, nframes.int * sizeof(float32))

proc addBuffer(src, dst: ptr UncheckedArray[float32], nframes: uint32) =
  for i in 0 ..< nframes.int:
    dst[i] = dst[i] + src[i]

proc copyBuffer(src, dst: ptr UncheckedArray[float32], nframes: uint32) =
  copyMem(dst, src, nframes.int * sizeof(float32))

proc processChannels(entry: ptr AudioProcessEntry): uint32 =
  case entry.ioMode
  of aimMonoLeftToStereo: 1'u32
  of aimStereo: 2'u32
  of aimBypass: 0'u32

proc duplicateMonoOutput(
    plan: ptr ProcessPlan,
    op: ProcessPlanOp,
    in1, in2, out1, out2: pointer,
    nframes: uint32,
) =
  let left = plan.opSlotPointer(op.dstBuffer, in1, in2, out1, out2)
  let right = plan.opSlotPointer(op.dstBuffer2, in1, in2, out1, out2)
  if not left.isNil and not right.isNil and left != right:
    copyBuffer(left, right, nframes)

proc copyProcessInputsToOutputs(
    plan: ptr ProcessPlan,
    op: ProcessPlanOp,
    in1, in2, out1, out2: pointer,
    nframes: uint32,
): bool =
  for channel in 0'u32 ..< op.channelCount:
    let src = plan.opSlotPointer(op.opBufferIndex(true, channel), in1, in2, out1, out2)
    let dst = plan.opSlotPointer(op.opBufferIndex(false, channel), in1, in2, out1, out2)
    if src.isNil or dst.isNil:
      return false
    copyBuffer(src, dst, nframes)
  true

proc runProcessOp(
    plan: ptr ProcessPlan,
    op: ProcessPlanOp,
    in1, in2, out1, out2: pointer,
    nframes: uint32,
): bool =
  if op.entryIndex >= plan.entryCount:
    return false
  let entry = addr plan.entries[op.entryIndex.int]
  let channels = entry.processChannels
  if channels == 0 or op.channelCount == 0 or op.channelCount > channels:
    return false

  if not entry.active:
    result = plan.copyProcessInputsToOutputs(op, in1, in2, out1, out2, nframes)
    if result and entry.ioMode == aimMonoLeftToStereo:
      plan.duplicateMonoOutput(op, in1, in2, out1, out2, nframes)
    return result

  let ops = cast[ptr PluginRuntimeOps](entry.ops)
  if ops.isNil or ops.process.isNil:
    return false

  var inputChannels: array[2, pointer]
  var outputChannels: array[2, pointer]
  for channel in 0'u32 ..< op.channelCount:
    let input =
      plan.opSlotPointer(op.opBufferIndex(true, channel), in1, in2, out1, out2)
    let output =
      plan.opSlotPointer(op.opBufferIndex(false, channel), in1, in2, out1, out2)
    if input.isNil or output.isNil:
      return false
    inputChannels[channel.int] = cast[pointer](input)
    outputChannels[channel.int] = cast[pointer](output)

  var inputBuses = [
    PluginAudioBus(
      portId: NullPortId,
      channels: cast[ptr UncheckedArray[pointer]](addr inputChannels[0]),
      channelCount: op.channelCount,
    )
  ]
  var outputBuses = [
    PluginAudioBus(
      portId: NullPortId,
      channels: cast[ptr UncheckedArray[pointer]](addr outputChannels[0]),
      channelCount: op.channelCount,
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
    plan.duplicateMonoOutput(op, in1, in2, out1, out2, nframes)
  true

proc tryProcessPlan*(
    plan: ptr ProcessPlan, in1, in2, out1, out2: pointer, nframes: uint32
): bool =
  if plan.isNil or plan.opCount == 0:
    return false

  for i in 0 ..< plan.opCount.int:
    let op = plan.ops[i]
    case op.kind
    of pokClear:
      let dst = plan.opSlotPointer(op.dstBuffer, in1, in2, out1, out2)
      if dst.isNil:
        return false
      clearBuffer(dst, nframes)
    of pokCopy:
      let src = plan.opSlotPointer(op.srcBuffer, in1, in2, out1, out2)
      let dst = plan.opSlotPointer(op.dstBuffer, in1, in2, out1, out2)
      if src.isNil or dst.isNil:
        return false
      copyBuffer(src, dst, nframes)
    of pokAdd:
      let src = plan.opSlotPointer(op.srcBuffer, in1, in2, out1, out2)
      let dst = plan.opSlotPointer(op.dstBuffer, in1, in2, out1, out2)
      if src.isNil or dst.isNil:
        return false
      addBuffer(src, dst, nframes)
    of pokProcess:
      if not plan.runProcessOp(op, in1, in2, out1, out2, nframes):
        return false
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
