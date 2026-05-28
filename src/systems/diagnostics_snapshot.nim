import ../audio/callback_diagnostics
import ../types/[audio_values, diagnostic_values, graph_values, ui_values]

proc buildGraphHealthSnapshot*(report: GraphCompileReport): GraphHealthSnapshot =
  result.compileErrorCount = report.errorCount
  if report.errorCount > 0:
    result.flags.incl(ghfCompileErrors)
  if report.errorOverflowed:
    result.flags.incl(ghfCompileErrorOverflow)
  for i in 0 ..< report.errorCount.int:
    if report.errors[i].kind == gcePlanCapacityExceeded:
      result.flags.incl(ghfPlanCapacityExceeded)

proc buildRuntimeDiagnosticsSnapshot*(
    audio: AudioCallbackDiagnosticsSnapshot, graphReport: GraphCompileReport
): RuntimeDiagnosticsSnapshot =
  RuntimeDiagnosticsSnapshot(audio: audio, graph: buildGraphHealthSnapshot(graphReport))

proc buildRuntimeDiagnosticsSnapshot*(
    diagnostics: var AudioCallbackDiagnostics, graphReport: GraphCompileReport
): RuntimeDiagnosticsSnapshot =
  buildRuntimeDiagnosticsSnapshot(
    diagnostics.loadAudioCallbackDiagnostics(), graphReport
  )

proc audioSnapshotMsg*(snapshot: RuntimeDiagnosticsSnapshot): Msg =
  Msg(kind: msgAudioSnapshot, diagnostics: snapshot)
