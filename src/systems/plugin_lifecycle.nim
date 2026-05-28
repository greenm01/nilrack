import ../plugins/clap_host
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
  if runtime.pluginId == NullPluginId or runtime.runtime.isNil or runtime.ops.isNil:
    return false
  let existing = store.findRuntimeIndex(runtime.pluginId)
  if existing >= 0:
    store.runtimes[existing] = runtime
    return true
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

proc unloadPluginRuntime*(store: var PluginRuntimeStore, pluginId: PluginId): bool =
  let index = store.findRuntimeIndex(pluginId)
  if index < 0:
    return false
  let runtime = store.removeRuntimeAt(index)
  if not runtime.ops.isNil and not runtime.ops.destroy.isNil:
    runtime.ops.destroy(runtime.runtime)
  true

proc loadClapRuntime*(
    store: var PluginRuntimeStore, pluginId: PluginId, pluginPath: string
): PluginLifecycleResult =
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
  if runtime.isNil or runtime.ops.isNil or runtime.ops.activate.isNil:
    return prsFailed
  runtime.ops.activate(runtime.runtime, sampleRate, minFrames, maxFrames)

proc startPluginRuntimeProcessing*(
    store: var PluginRuntimeStore, pluginId: PluginId
): PluginRuntimeStatus =
  let runtime = store.runtimeForPlugin(pluginId)
  if runtime.isNil or runtime.ops.isNil or runtime.ops.startProcessing.isNil:
    return prsFailed
  runtime.ops.startProcessing(runtime.runtime)

proc stopPluginRuntimeProcessing*(
    store: var PluginRuntimeStore, pluginId: PluginId
): PluginRuntimeStatus =
  let runtime = store.runtimeForPlugin(pluginId)
  if runtime.isNil or runtime.ops.isNil or runtime.ops.stopProcessing.isNil:
    return prsFailed
  runtime.ops.stopProcessing(runtime.runtime)

proc deactivatePluginRuntime*(
    store: var PluginRuntimeStore, pluginId: PluginId
): PluginRuntimeStatus =
  let runtime = store.runtimeForPlugin(pluginId)
  if runtime.isNil or runtime.ops.isNil or runtime.ops.deactivate.isNil:
    return prsFailed
  runtime.ops.deactivate(runtime.runtime)
