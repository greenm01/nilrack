import ../plugins/clap_host
import ../plugins/plugin_runtime_api
import ../key_ops
import ../types/model
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

proc stateBlobWriter(
    ctx: pointer, data: pointer, byteCount: uint64
): bool {.nimcall, gcsafe, raises: [].} =
  if ctx.isNil:
    return false
  if byteCount == 0:
    return true
  if data.isNil or byteCount > high(int).uint64:
    return false
  try:
    let stateRef = cast[ptr StateBlobRef](ctx)
    let oldLen = stateRef.data.len
    stateRef.data.setLen(oldLen + byteCount.int)
    copyMem(addr stateRef.data[oldLen], data, byteCount.int)
    true
  except CatchableError:
    false

proc savePluginRuntimeState*(
    store: var PluginRuntimeStore, pluginId: PluginId, stateRef: var StateBlobRef
): PluginRuntimeStatus =
  let runtime = store.runtimeForPlugin(pluginId)
  if runtime.isNil:
    return prsFailed
  let ops = runtime[].runtimeOps()
  if ops.isNil or ops.saveState.isNil:
    return prsFailed
  stateRef.data.setLen(0)
  ops.saveState(runtime.runtime, stateBlobWriter, addr stateRef)

proc loadPluginRuntimeState*(
    store: var PluginRuntimeStore, pluginId: PluginId, stateRef: StateBlobRef
): PluginRuntimeStatus =
  let runtime = store.runtimeForPlugin(pluginId)
  if runtime.isNil:
    return prsFailed
  let ops = runtime[].runtimeOps()
  if ops.isNil or ops.loadState.isNil:
    return prsFailed
  let data =
    if stateRef.data.len == 0:
      nil
    else:
      cast[pointer](unsafeAddr stateRef.data[0])
  ops.loadState(runtime.runtime, data, stateRef.data.len.uint64)

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
