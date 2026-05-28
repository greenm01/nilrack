import std/unittest

import ../src/audio/[backend_reconfiguration, callback_diagnostics, process_plan_store]
import ../src/types/audio_values

suite "backend reconfiguration":
  test "records reconfiguration requests in fixed atomics":
    var backend: JackBackend
    backend.planSlot.initProcessPlanSlot()
    backend.diagnostics.initAudioCallbackDiagnostics()
    backend.reconfiguration.initAudioReconfigurationState(48000, 64)

    backend.requestAudioReconfiguration(96000, 128)

    let request = backend.loadAudioReconfigurationRequest()
    let diagnostics = backend.diagnostics.loadAudioCallbackDiagnostics()

    check request.generation == 1
    check request.sampleRate == 96000
    check request.bufferSize == 128
    check diagnostics.diagnosticCount(adkReconfigRequested) == 1

  test "partial backend changes preserve the paired atomic value":
    var backend: JackBackend
    backend.diagnostics.initAudioCallbackDiagnostics()
    backend.reconfiguration.initAudioReconfigurationState(48000, 64)

    backend.requestSampleRateReconfiguration(96000)
    check backend.loadAudioReconfigurationRequest().sampleRate == 96000
    check backend.loadAudioReconfigurationRequest().bufferSize == 64

    backend.requestBufferSizeReconfiguration(256)
    check backend.loadAudioReconfigurationRequest().sampleRate == 96000
    check backend.loadAudioReconfigurationRequest().bufferSize == 256

  test "consumes reconfiguration off callback and clears published plan":
    var backend: JackBackend
    var plan: ProcessPlan
    var lastSeen: uint32
    backend.planSlot.initProcessPlanSlot()
    backend.diagnostics.initAudioCallbackDiagnostics()
    backend.reconfiguration.initAudioReconfigurationState(48000, 64)
    discard backend.planSlot.publishProcessPlan(addr plan)

    check not backend.consumeAudioReconfigurationRequest(lastSeen)
    check backend.planSlot.loadProcessPlan() == addr plan

    backend.requestAudioReconfiguration(44100, 256)

    check backend.consumeAudioReconfigurationRequest(lastSeen)
    check lastSeen == 1
    check backend.sampleRate == 44100
    check backend.bufferSize == 256
    check backend.planSlot.loadProcessPlan().isNil
