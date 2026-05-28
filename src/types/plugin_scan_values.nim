const PluginScanTimeoutMs* = 5000

type
  PluginScanFailureReason* = enum
    psfrNone
    psfrTimeout
    psfrNonZeroExit
    psfrEmptyOutput
    psfrMalformedKdl

  PluginScanProcessResult* = object
    ok*: bool
    reason*: PluginScanFailureReason
    exitCode*: int
    timedOut*: bool
    output*: string
    error*: string

  PluginScanFailedEntry* = object
    path*: string
    mtime*: int64
    reason*: PluginScanFailureReason
    exitCode*: int
    timedOut*: bool
    error*: string
