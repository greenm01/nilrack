import std/[os, unittest]

import ../src/systems/plugin_lifecycle
import ../src/types/[core, plugin_runtime_values]

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
      pluginId: PluginId(1), runtime: addr marker, ops: cast[ptr PluginRuntimeOps](1)
    )

    check store.addPluginRuntime(runtime)
    check store.count == 1
    check store.runtimeForPlugin(PluginId(1)) != nil
    check store.runtimeForPlugin(PluginId(2)).isNil

  let pluginPath = localClapPath()
  if pluginPath.len == 0:
    echo "SKIP: no CLAP plugin found; set NILRACK_TEST_CLAP"
  else:
    test "loads activates stops and unloads CLAP through runtime store":
      var store: PluginRuntimeStore
      let pluginId = PluginId(7)

      let loaded = store.loadClapRuntime(pluginId, pluginPath)
      check loaded.ok
      check store.runtimeForPlugin(pluginId) != nil

      check store.activatePluginRuntime(pluginId, 48000.0, 1, 64) == prsOk
      check store.startPluginRuntimeProcessing(pluginId) == prsOk
      check store.stopPluginRuntimeProcessing(pluginId) == prsOk
      check store.deactivatePluginRuntime(pluginId) == prsOk
      check store.unloadPluginRuntime(pluginId)
      check store.runtimeForPlugin(pluginId).isNil
