import ../types/audio_values

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
  if not entry.active or entry.ioMode == aimBypass or entry.processBlock.isNil:
    return false

  entry.processBlock(entry.runtime, in1, in2, out1, out2, nframes, entry.ioMode)

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
