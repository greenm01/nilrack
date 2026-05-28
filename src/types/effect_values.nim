import core

const MaxEffectQueueEntries* = 128

type
  EffectKind* = enum
    ekGraphDirty
    ekProcessPlanDirty
    ekTopologyRefresh
    ekDiagnosticsDirty
    ekStateDirty

  Effect* = object
    kind*: EffectKind
    rackId*: RackId
    pluginId*: PluginId

  EffectQueue* = object
    count*: uint32
    entries*: array[MaxEffectQueueEntries, Effect]
    overflowed*: bool
