import std/unittest

import ../src/audio/callback_diagnostics
import ../src/systems/[diagnostics_snapshot, graph_compile]
import ../src/types/[audio_values, core, diagnostic_values, ui_values]

suite "diagnostics snapshot":
  test "combines audio counters and graph health flags":
    var diagnostics: AudioCallbackDiagnostics
    diagnostics.initAudioCallbackDiagnostics()
    diagnostics.incrementAudioDiagnostic(adkStaleEvent)

    var graphReport = initGraphCompileReport(RackId(1))
    discard graphReport.reportPlanCapacityExceeded(RackId(1))

    let snapshot = diagnostics.buildRuntimeDiagnosticsSnapshot(graphReport)

    check snapshot.audio.generation == 1
    check snapshot.audio.diagnosticCount(adkStaleEvent) == 1
    check snapshot.graph.compileErrorCount == 1
    check ghfCompileErrors in snapshot.graph.flags
    check ghfPlanCapacityExceeded in snapshot.graph.flags

  test "reports compile error overflow as graph health":
    var graphReport = initGraphCompileReport(RackId(1))
    graphReport.errorOverflowed = true

    let snapshot =
      buildRuntimeDiagnosticsSnapshot(AudioCallbackDiagnosticsSnapshot(), graphReport)

    check ghfCompileErrorOverflow in snapshot.graph.flags

  test "wraps diagnostics snapshot in a UI message":
    let snapshot = RuntimeDiagnosticsSnapshot()
    let msg = audioSnapshotMsg(snapshot)

    check msg.kind == msgAudioSnapshot
    check msg.diagnostics.audio.generation == 0
