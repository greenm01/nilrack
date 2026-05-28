import std/[strutils, unittest]

import ../src/types/[core, plugin_runtime_values]

proc okActivate(
    runtime: pointer, sampleRate: float64, minFrames, maxFrames: uint32
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  discard runtime
  discard sampleRate
  discard minFrames
  discard maxFrames
  prsOk

proc okSimple(runtime: pointer): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  discard runtime
  prsOk

proc okProcess(
    runtime: pointer, context: pointer
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  discard runtime
  discard context
  prsOk

proc okDestroy(runtime: pointer) {.nimcall, gcsafe, raises: [].} =
  discard runtime

suite "plugin runtime ops":
  test "ops table accepts fixed no-raise function pointers":
    var ops = PluginRuntimeOps(
      activate: okActivate,
      deactivate: okSimple,
      startProcessing: okSimple,
      stopProcessing: okSimple,
      process: okProcess,
      destroy: okDestroy,
    )
    let runtime = PluginRuntimeRef(pluginId: PluginId(1), runtime: nil, ops: addr ops)

    check runtime.pluginId == PluginId(1)
    check runtime.ops.activate(runtime.runtime, 48000.0, 1, 64) == prsOk
    check runtime.ops.process(runtime.runtime, nil) == prsOk

  test "runtime ops type module stays boundary-safe":
    let source = readFile("src/types/plugin_runtime_values.nim")

    for forbidden in ["seq", "ref object", "closure", "raise ", "raise(", "except"]:
      checkpoint "plugin runtime values must not contain " & forbidden
      check not source.contains(forbidden)

    check source.contains("raises: []")
    check source.contains("nimcall")
