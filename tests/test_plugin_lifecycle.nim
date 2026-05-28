import std/[os, unittest]

import ../src/plugins/plugin_runtime_api
import ../src/systems/plugin_lifecycle
import ../src/types/model
import ../src/types/[core, plugin_runtime_values]

type FakeRuntime = object
  saved*: array[4, byte]
  loaded*: array[4, byte]
  loadedByteCount*: uint64

proc testProcess(
    runtime: pointer, context: ptr ProcessContext
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  discard runtime
  discard context
  prsOk

proc testSaveState(
    runtime: pointer, writer: PluginRuntimeStateWriteProc, writerCtx: pointer
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  if runtime.isNil or writer.isNil:
    return prsFailed
  let fake = cast[ptr FakeRuntime](runtime)
  if writer(writerCtx, cast[pointer](addr fake.saved[0]), fake.saved.len.uint64):
    prsOk
  else:
    prsFailed

proc testLoadState(
    runtime: pointer, data: pointer, byteCount: uint64
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  if runtime.isNil or data.isNil or byteCount != 4:
    return prsFailed
  let fake = cast[ptr FakeRuntime](runtime)
  copyMem(addr fake.loaded[0], data, byteCount.int)
  fake.loadedByteCount = byteCount
  prsOk

proc localClapPath(): string =
  let envPath = getEnv("NILRACK_TEST_CLAP")
  if envPath.len > 0:
    return envPath
  let nilamp = "/home/niltempus/dev/nilamp/native/bin/nilamp-twd-mkii.clap"
  if fileExists(nilamp):
    return nilamp
  ""

suite "plugin lifecycle":
  test "runtime store keeps plugin refs in bounded storage":
    var store: PluginRuntimeStore
    var marker: int
    var ops = PluginRuntimeOps(process: testProcess)
    let runtime = PluginRuntimeRef(
      pluginId: PluginId(1), runtime: addr marker, ops: cast[pointer](addr ops)
    )

    check store.addPluginRuntime(runtime)
    check not store.addPluginRuntime(runtime)
    check store.count == 1
    check store.runtimeForPlugin(PluginId(1)) != nil
    check store.runtimeForPlugin(PluginId(2)).isNil

  test "runtime state helpers save and load through ops":
    var store: PluginRuntimeStore
    var fake = FakeRuntime(saved: [1'u8, 2'u8, 3'u8, 4'u8])
    var ops = PluginRuntimeOps(
      process: testProcess, saveState: testSaveState, loadState: testLoadState
    )
    let runtime = PluginRuntimeRef(
      pluginId: PluginId(1), runtime: addr fake, ops: cast[pointer](addr ops)
    )
    check store.addPluginRuntime(runtime)

    var stateRef: StateBlobRef
    check store.savePluginRuntimeState(PluginId(1), stateRef) == prsOk
    check stateRef.data == @[1'u8, 2'u8, 3'u8, 4'u8]

    check store.loadPluginRuntimeState(PluginId(1), stateRef) == prsOk
    check fake.loaded == [1'u8, 2'u8, 3'u8, 4'u8]
    check fake.loadedByteCount == 4

  test "runtime state helpers fail for missing runtime or missing ops":
    var store: PluginRuntimeStore
    var fake: FakeRuntime
    var ops = PluginRuntimeOps(process: testProcess)
    let runtime = PluginRuntimeRef(
      pluginId: PluginId(1), runtime: addr fake, ops: cast[pointer](addr ops)
    )
    var stateRef = StateBlobRef(data: @[1'u8])

    check store.savePluginRuntimeState(PluginId(99), stateRef) == prsFailed
    check store.loadPluginRuntimeState(PluginId(99), stateRef) == prsFailed
    check store.addPluginRuntime(runtime)
    check store.savePluginRuntimeState(PluginId(1), stateRef) == prsFailed
    check store.loadPluginRuntimeState(PluginId(1), stateRef) == prsFailed

  let pluginPath = localClapPath()
  if pluginPath.len == 0:
    echo "SKIP: no CLAP plugin found; set NILRACK_TEST_CLAP"
  else:
    test "loads activates stops and retires CLAP through runtime store":
      var store: PluginRuntimeStore
      let pluginId = PluginId(7)

      let loaded = store.loadClapRuntime(pluginId, pluginPath)
      check loaded.ok
      check store.runtimeForPlugin(pluginId) != nil

      check store.activatePluginRuntime(pluginId, 48000.0, 1, 64) == prsOk
      check store.startPluginRuntimeProcessing(pluginId) == prsOk
      check store.stopPluginRuntimeProcessing(pluginId) == prsOk
      check store.deactivatePluginRuntime(pluginId) == prsOk
      if loaded.descriptor.hasState:
        var stateRef: StateBlobRef
        check store.savePluginRuntimeState(pluginId, stateRef) == prsOk
        check store.loadPluginRuntimeState(pluginId, stateRef) == prsOk
      var retiredRuntime: PluginRuntimeRef
      check store.retirePluginRuntime(pluginId, retiredRuntime)
      check store.runtimeForPlugin(pluginId).isNil
      retiredRuntime.destroyPluginRuntime()
