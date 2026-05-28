import std/unittest

import ../src/audio/callback_diagnostics
import ../src/types/audio_values

suite "audio callback diagnostics":
  test "initializes fixed counters and generation":
    var diagnostics: AudioCallbackDiagnostics
    diagnostics.initAudioCallbackDiagnostics()

    let snapshot = diagnostics.loadAudioCallbackDiagnostics()

    check snapshot.generation == 0
    for kind in AudioDiagnosticKind:
      check snapshot.diagnosticCount(kind) == 0

  test "increments counters and bumps generation":
    var diagnostics: AudioCallbackDiagnostics
    diagnostics.initAudioCallbackDiagnostics()

    diagnostics.incrementAudioDiagnostic(adkStaleEvent)
    diagnostics.incrementAudioDiagnostic(adkStaleEvent)
    diagnostics.incrementAudioDiagnostic(adkPluginProcessError)

    let snapshot = diagnostics.loadAudioCallbackDiagnostics()

    check snapshot.generation == 3
    check snapshot.diagnosticCount(adkStaleEvent) == 2
    check snapshot.diagnosticCount(adkPluginProcessError) == 1
    check snapshot.diagnosticCount(adkQueueFull) == 0
