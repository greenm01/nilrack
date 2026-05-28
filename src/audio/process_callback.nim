import std/atomics
import ../types/audio_values
import process_plan_audio
import process_plan_store

var meterLevels*: array[4, Atomic[float32]]

# These are set by jack_backend.initJackBackend before activation.
# The callback runs on the JACK audio thread — no allocation, no logging.
var gBackendPtr*: ptr JackBackend = nil

type JackPort {.importc: "jack_port_t", header: "jack/jack.h".} = object

proc jackPortGetBuffer(
  port: ptr JackPort, nframes: uint32
): pointer {.importc: "jack_port_get_buffer", header: "jack/jack.h".}

proc jackProcess*(nframes: uint32, arg: pointer): cint {.cdecl.} =
  let b = cast[ptr JackBackend](arg)
  let in1 = cast[ptr UncheckedArray[float32]](jackPortGetBuffer(
    cast[ptr JackPort](b.inPort1), nframes
  ))
  let in2 = cast[ptr UncheckedArray[float32]](jackPortGetBuffer(
    cast[ptr JackPort](b.inPort2), nframes
  ))
  let out1 = cast[ptr UncheckedArray[float32]](jackPortGetBuffer(
    cast[ptr JackPort](b.outPort1), nframes
  ))
  let out2 = cast[ptr UncheckedArray[float32]](jackPortGetBuffer(
    cast[ptr JackPort](b.outPort2), nframes
  ))
  let plan = b.planSlot.loadProcessPlan()
  discard processAudioBlock(plan, in1, in2, out1, out2, nframes)
  var inPeak, outPeak = 0.0'f32
  for i in 0 ..< nframes.int:
    let inA1 = abs(in1[i])
    let inA2 = abs(in2[i])
    let outA1 = abs(out1[i])
    let outA2 = abs(out2[i])
    if inA1 > inPeak:
      inPeak = inA1
    if inA2 > inPeak:
      inPeak = inA2
    if outA1 > outPeak:
      outPeak = outA1
    if outA2 > outPeak:
      outPeak = outA2
  meterLevels[0].store(inPeak, moRelaxed)
  meterLevels[1].store(outPeak, moRelaxed)
  discard b.planSlot.advanceCallbackEpoch()
  0
