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
