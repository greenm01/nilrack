import ../plugins/clap_host
import ../plugins/plugin_runtime_api
import ../key_ops
import ../types/[core, plugin_runtime_values, plugin_values]

type PluginLifecycleResult* = object
  ok*: bool
  error*: string
  descriptor*: PluginDescriptor

proc findRuntimeIndex(store: PluginRuntimeStore, pluginId: PluginId): int =
  for i in 0 ..< store.count.int:
    if store.runtimes[i].pluginId == pluginId:
      return i
  -1

proc runtimeForPlugin*(
    store: var PluginRuntimeStore, pluginId: PluginId
): ptr PluginRuntimeRef =
  let index = store.findRuntimeIndex(pluginId)
  if index < 0:
    return nil
  addr store.runtimes[index]

proc addPluginRuntime*(store: var PluginRuntimeStore, runtime: PluginRuntimeRef): bool =
  if runtime.pluginId == NullPluginId or not runtime.hasRuntimeProcess:
    return false
  let existing = store.findRuntimeIndex(runtime.pluginId)
  if existing >= 0:
    return false
  if store.count >= MaxPluginRuntimes.uint32:
    store.capacityExceeded = true
    return false
  store.runtimes[store.count.int] = runtime
  inc store.count
  true

proc removeRuntimeAt(store: var PluginRuntimeStore, index: int): PluginRuntimeRef =
  result = store.runtimes[index]
  let last = store.count.int - 1
  for i in index ..< last:
    store.runtimes[i] = store.runtimes[i + 1]
  store.runtimes[last] = PluginRuntimeRef()
  dec store.count

proc retirePluginRuntime*(
    store: var PluginRuntimeStore,
    pluginId: PluginId,
    retiredRuntime: var PluginRuntimeRef,
): bool =
  let index = store.findRuntimeIndex(pluginId)
  if index < 0:
    retiredRuntime = PluginRuntimeRef()
    return false
  retiredRuntime = store.removeRuntimeAt(index)
  true

proc destroyPluginRuntime*(runtime: PluginRuntimeRef) =
  let ops = runtime.runtimeOps()
  if not ops.isNil and not ops.destroy.isNil:
    ops.destroy(runtime.runtime)

proc loadClapRuntime*(
    store: var PluginRuntimeStore, pluginId: PluginId, pluginPath: string
): PluginLifecycleResult =
  if not store.runtimeForPlugin(pluginId).isNil:
    return PluginLifecycleResult(ok: false, error: "plugin runtime already exists")
  let loaded = loadClapPlugin(pluginPath)
  if not loaded.ok:
    return PluginLifecycleResult(ok: false, error: loaded.error)
  loaded.plugin.bindClapPluginId(pluginId)
  if not store.addPluginRuntime(loaded.plugin.clapPluginRuntimeRef(pluginId)):
    loaded.plugin.close()
    return PluginLifecycleResult(ok: false, error: "plugin runtime store is full")
  PluginLifecycleResult(ok: true, descriptor: loaded.descriptor)

proc activatePluginRuntime*(
    store: var PluginRuntimeStore,
    pluginId: PluginId,
    sampleRate: float64,
    minFrames, maxFrames: uint32,
): PluginRuntimeStatus =
  let runtime = store.runtimeForPlugin(pluginId)
  if runtime.isNil:
    return prsFailed
  let ops = runtime[].runtimeOps()
  if ops.isNil or ops.activate.isNil:
    return prsFailed
  ops.activate(runtime.runtime, sampleRate, minFrames, maxFrames)

proc startPluginRuntimeProcessing*(
    store: var PluginRuntimeStore, pluginId: PluginId
): PluginRuntimeStatus =
  let runtime = store.runtimeForPlugin(pluginId)
  if runtime.isNil:
    return prsFailed
  let ops = runtime[].runtimeOps()
  if ops.isNil or ops.startProcessing.isNil:
    return prsFailed
  ops.startProcessing(runtime.runtime)

proc stopPluginRuntimeProcessing*(
    store: var PluginRuntimeStore, pluginId: PluginId
): PluginRuntimeStatus =
  let runtime = store.runtimeForPlugin(pluginId)
  if runtime.isNil:
    return prsFailed
  let ops = runtime[].runtimeOps()
  if ops.isNil or ops.stopProcessing.isNil:
    return prsFailed
  ops.stopProcessing(runtime.runtime)

proc deactivatePluginRuntime*(
    store: var PluginRuntimeStore, pluginId: PluginId
): PluginRuntimeStatus =
  let runtime = store.runtimeForPlugin(pluginId)
  if runtime.isNil:
    return prsFailed
  let ops = runtime[].runtimeOps()
  if ops.isNil or ops.deactivate.isNil:
    return prsFailed
  ops.deactivate(runtime.runtime)
