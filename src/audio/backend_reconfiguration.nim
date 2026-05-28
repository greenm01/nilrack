import std/atomics
import ../types/audio_values
import callback_diagnostics
import process_plan_store

proc initAudioReconfigurationState*(
    state: var AudioReconfigurationState, sampleRate, bufferSize: uint32
) =
  state.generation.store(0'u32, moRelaxed)
  state.sampleRate.store(sampleRate, moRelaxed)
  state.bufferSize.store(bufferSize, moRelaxed)

proc requestAudioReconfiguration*(
    backend: var JackBackend, sampleRate, bufferSize: uint32
) =
  backend.reconfiguration.sampleRate.store(sampleRate, moRelaxed)
  backend.reconfiguration.bufferSize.store(bufferSize, moRelaxed)
  discard backend.reconfiguration.generation.fetchAdd(1'u32, moRelease)
  backend.diagnostics.incrementAudioDiagnostic(adkReconfigRequested)

proc requestSampleRateReconfiguration*(backend: var JackBackend, sampleRate: uint32) =
  backend.requestAudioReconfiguration(
    sampleRate, backend.reconfiguration.bufferSize.load(moAcquire)
  )

proc requestBufferSizeReconfiguration*(backend: var JackBackend, bufferSize: uint32) =
  backend.requestAudioReconfiguration(
    backend.reconfiguration.sampleRate.load(moAcquire), bufferSize
  )

proc loadAudioReconfigurationRequest*(
    backend: var JackBackend
): AudioReconfigurationRequest =
  result.generation = backend.reconfiguration.generation.load(moAcquire)
  result.sampleRate = backend.reconfiguration.sampleRate.load(moAcquire)
  result.bufferSize = backend.reconfiguration.bufferSize.load(moAcquire)

proc consumeAudioReconfigurationRequest*(
    backend: var JackBackend,
    lastSeenGeneration: var uint32,
    retiredPlan: var ptr ProcessPlan,
): bool =
  let request = backend.loadAudioReconfigurationRequest()
  if request.generation == lastSeenGeneration:
    retiredPlan = nil
    return false
  lastSeenGeneration = request.generation
  backend.sampleRate = request.sampleRate
  backend.bufferSize = request.bufferSize
  backend.reconfiguration.sampleRate.store(request.sampleRate, moRelaxed)
  backend.reconfiguration.bufferSize.store(request.bufferSize, moRelaxed)
  retiredPlan = backend.planSlot.clearProcessPlan()
  true

proc consumeAudioReconfigurationRequest*(
    backend: var JackBackend, lastSeenGeneration: var uint32
): bool =
  var retiredPlan: ptr ProcessPlan
  backend.consumeAudioReconfigurationRequest(lastSeenGeneration, retiredPlan)
