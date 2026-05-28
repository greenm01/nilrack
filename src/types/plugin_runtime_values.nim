import core

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
    runtime: pointer, context: pointer
  ): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].}

  PluginRuntimeDestroyProc* = proc(runtime: pointer) {.nimcall, gcsafe, raises: [].}

  PluginRuntimeOps* = object
    activate*: PluginRuntimeActivateProc
    deactivate*: PluginRuntimeSimpleProc
    startProcessing*: PluginRuntimeSimpleProc
    stopProcessing*: PluginRuntimeSimpleProc
    process*: PluginRuntimeProcessProc
    destroy*: PluginRuntimeDestroyProc

  PluginRuntimeRef* = object
    pluginId*: PluginId
    runtime*: pointer
    ops*: ptr PluginRuntimeOps
