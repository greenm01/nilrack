import std/unittest

import ../src/plugins/host_callbacks
import ../src/types/plugin_runtime_values

suite "plugin host callbacks":
  test "records host callback requests as one-shot flags":
    var callbacks: PluginHostCallbackFlags
    callbacks.initPluginHostCallbackFlags()

    callbacks.markPluginHostCallback(phcfRestart)
    callbacks.markPluginHostCallback(phcfProcess)
    callbacks.markPluginHostCallback(phcfStateDirty)

    let first = callbacks.takePluginHostCallbackSnapshot()
    let second = callbacks.takePluginHostCallbackSnapshot()

    check phcfRestart in first.flags
    check phcfProcess in first.flags
    check phcfStateDirty in first.flags
    check phcfTimer notin first.flags
    check second.flags == {}
