import std/[strutils, unittest]

const
  realtimeFiles = [
    "src/audio/audio_feedback.nim", "src/audio/backend_reconfiguration.nim",
    "src/audio/callback_diagnostics.nim", "src/audio/midi_event_buffer.nim",
    "src/audio/param_event_queue.nim", "src/audio/process_callback.nim",
    "src/audio/process_plan_audio.nim", "src/audio/process_plan_store.nim",
    "src/audio/process_plan_targets.nim", "src/audio/rt_queue.nim",
  ]

  allocationPatterns = [
    "newSeq", "newSeqOfCap", "alloc(", "realloc(", "dealloc(", ".add(", ".setLen(", "@["
  ]

  loggingPatterns = ["echo ", "writeLine", "stdout", "stderr"]
  lockPatterns = ["import std/locks", "initLock", "acquire(", "release("]
  modelAccessPatterns = ["NilrackModel", "../state", "state/"]

proc checkAbsent(path: string, source: string, patterns: openArray[string]) =
  for pattern in patterns:
    checkpoint path & " must not contain " & pattern
    check not source.contains(pattern)

suite "realtime audio rules":
  test "callback-adjacent audio modules do not allocate log lock or access model":
    for path in realtimeFiles:
      let source = readFile(path)
      checkAbsent(path, source, allocationPatterns)
      checkAbsent(path, source, loggingPatterns)
      checkAbsent(path, source, lockPatterns)
      checkAbsent(path, source, modelAccessPatterns)
