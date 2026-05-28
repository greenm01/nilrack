import std/unittest

import ../src/plugins/[clap_api, clap_host_callbacks]
import ../src/types/[core, plugin_runtime_values]

suite "clap host callbacks":
  test "fd and timer callbacks retain bound plugin identity":
    var hostBox = newClapHostBox()
    var event: PluginEventThreadEvent
    var timerId: ClapId

    hostBox.bindClapHostPluginId(PluginId(42))

    check hostBox.runtime.fdSupport.registerFd(addr hostBox.host, 9, 3)
    check hostBox.popClapHostBoxEvent(event)
    check event.kind == peteClapFdRegister
    check event.pluginId == PluginId(42)
    check event.fd == 9
    check event.fdFlags == 3

    check hostBox.runtime.timerSupport.registerTimer(
      addr hostBox.host, 20, addr timerId
    )
    check timerId == 1
    check hostBox.popClapHostBoxEvent(event)
    check event.kind == peteClapTimerRegister
    check event.pluginId == PluginId(42)
    check event.timerId == 1
    check event.periodMs == 20

  test "extension lookup exposes host support without queueing events":
    var hostBox = newClapHostBox()

    check not hostBox.host.getExtension(
      addr hostBox.host, ClapExtPosixFdSupport.cstring
    ).isNil
    check not hostBox.host.getExtension(addr hostBox.host, ClapExtTimerSupport.cstring).isNil
    check hostBox.host.getExtension(addr hostBox.host, "unknown".cstring).isNil
