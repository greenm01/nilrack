import std/[os, unittest]

import ../src/systems/plugin_lifecycle
import ../src/types/[audio_values, core, plugin_runtime_values]

proc testProcessBlock(
    runtime: pointer, in1, in2, out1, out2: pointer, nframes: uint32, mode: AudioIoMode
): bool {.nimcall, gcsafe, raises: [].} =
  discard runtime
  discard in1
  discard in2
  discard out1
  discard out2
  discard nframes
  discard mode
  true

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
    let runtime = PluginRuntimeRef(
      pluginId: PluginId(1),
      runtime: addr marker,
      ops: cast[ptr PluginRuntimeOps](1),
      processBlock: testProcessBlock,
    )

    check store.addPluginRuntime(runtime)
    check not store.addPluginRuntime(runtime)
    check store.count == 1
    check store.runtimeForPlugin(PluginId(1)) != nil
    check store.runtimeForPlugin(PluginId(2)).isNil

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
      var retiredRuntime: PluginRuntimeRef
      check store.retirePluginRuntime(pluginId, retiredRuntime)
      check store.runtimeForPlugin(pluginId).isNil
      retiredRuntime.destroyPluginRuntime()
