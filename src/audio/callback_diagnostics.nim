import std/atomics
import ../types/audio_values

proc initAudioCallbackDiagnostics*(diagnostics: var AudioCallbackDiagnostics) =
  diagnostics.generation.store(0'u32, moRelaxed)
  for kind in AudioDiagnosticKind:
    diagnostics.counters[kind].store(0'u32, moRelaxed)

proc incrementAudioDiagnostic*(
    diagnostics: var AudioCallbackDiagnostics, kind: AudioDiagnosticKind
) =
  discard diagnostics.counters[kind].fetchAdd(1'u32, moRelaxed)
  discard diagnostics.generation.fetchAdd(1'u32, moRelease)

proc loadAudioCallbackDiagnostics*(
    diagnostics: var AudioCallbackDiagnostics
): AudioCallbackDiagnosticsSnapshot =
  result.generation = diagnostics.generation.load(moAcquire)
  for kind in AudioDiagnosticKind:
    result.counters[kind] = diagnostics.counters[kind].load(moAcquire)

proc diagnosticCount*(
    snapshot: AudioCallbackDiagnosticsSnapshot, kind: AudioDiagnosticKind
): uint32 =
  snapshot.counters[kind]
