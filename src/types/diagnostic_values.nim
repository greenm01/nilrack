import audio_values

type
  GraphHealthFlag* = enum
    ghfCompileErrors
    ghfCompileErrorOverflow
    ghfPlanCapacityExceeded

  GraphHealthSnapshot* = object
    flags*: set[GraphHealthFlag]
    compileErrorCount*: uint32

  RuntimeDiagnosticsSnapshot* = object
    audio*: AudioCallbackDiagnosticsSnapshot
    graph*: GraphHealthSnapshot
