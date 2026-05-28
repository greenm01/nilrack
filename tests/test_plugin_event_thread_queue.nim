import std/unittest

import ../src/plugins/plugin_event_thread_queue
import ../src/types/[core, plugin_runtime_values]

suite "plugin event thread queue":
  test "routes CLAP fd and timer events through bounded queue":
    var queue: PluginEventThreadQueue
    var event: PluginEventThreadEvent

    check queue.enqueuePluginEventThreadEvent(
      PluginEventThreadEvent(
        kind: peteClapFdRegister, pluginId: PluginId(1), fd: 9, fdFlags: 3
      )
    )
    check queue.enqueuePluginEventThreadEvent(
      PluginEventThreadEvent(
        kind: peteClapTimerRegister, pluginId: PluginId(1), timerId: 4, periodMs: 20
      )
    )

    check queue.dequeuePluginEventThreadEvent(event)
    check event.kind == peteClapFdRegister
    check event.fd == 9
    check event.fdFlags == 3

    check queue.dequeuePluginEventThreadEvent(event)
    check event.kind == peteClapTimerRegister
    check event.timerId == 4
    check event.periodMs == 20

  test "plugin event thread queue remains bounded":
    var queue: PluginEventThreadQueue

    for i in 0 ..< MaxPluginEventThreadEvents - 1:
      check queue.enqueuePluginEventThreadEvent(
        PluginEventThreadEvent(kind: peteClapFdModify, fd: i.int32)
      )

    check not queue.enqueuePluginEventThreadEvent(
      PluginEventThreadEvent(kind: peteClapFdModify, fd: 999)
    )
