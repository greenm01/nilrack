import ../audio/process_context
import ../types/[core, plugin_runtime_values]

export process_context

type
  PluginRuntimeStatus* = enum
    prsOk
    prsBypass
    prsFailed

  PluginRuntimeActivateProc* = proc(
    runtime: pointer, sampleRate: float64, minFrames, maxFrames: uint32
  ): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].}

  PluginRuntimeSimpleProc* =
    proc(runtime: pointer): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].}

  PluginRuntimeProcessProc* = proc(
    runtime: pointer, context: ptr ProcessContext
  ): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].}

  PluginRuntimeDestroyProc* = proc(runtime: pointer) {.nimcall, gcsafe, raises: [].}

  PluginRuntimeOps* = object
    activate*: PluginRuntimeActivateProc
    deactivate*: PluginRuntimeSimpleProc
    startProcessing*: PluginRuntimeSimpleProc
    stopProcessing*: PluginRuntimeSimpleProc
    process*: PluginRuntimeProcessProc
    destroy*: PluginRuntimeDestroyProc

proc pluginRuntimeRef*(
    pluginId: PluginId, runtime: pointer, ops: ptr PluginRuntimeOps
): PluginRuntimeRef =
  PluginRuntimeRef(pluginId: pluginId, runtime: runtime, ops: cast[pointer](ops))

proc runtimeOps*(runtime: PluginRuntimeRef): ptr PluginRuntimeOps =
  cast[ptr PluginRuntimeOps](runtime.ops)

proc hasRuntimeProcess*(runtime: PluginRuntimeRef): bool =
  let ops = runtime.runtimeOps()
  not runtime.runtime.isNil and not ops.isNil and not ops.process.isNil
