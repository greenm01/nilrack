import std/[os, unittest]

import ../src/plugins/clap_host
import ../src/types/model

proc localClapPath(): string =
  let envPath = getEnv("NILRACK_TEST_CLAP")
  if envPath.len > 0:
    return envPath
  let nilamp = "/home/niltempus/dev/nilamp/native/bin/nilamp-twd-mkii.clap"
  if fileExists(nilamp):
    return nilamp
  ""

suite "CLAP host":
  test "resolves direct CLAP shared-library paths":
    let path = "/tmp/plugin.clap"
    check clapLibraryPath(path) == path

  let pluginPath = localClapPath()
  if pluginPath.len == 0:
    echo "SKIP: no CLAP plugin found; set NILRACK_TEST_CLAP"
  else:
    test "loads descriptor, ports, params, and state capability":
      let loaded = loadClapPlugin(pluginPath)
      check loaded.ok
      if loaded.ok:
        check loaded.descriptor.api == paClap
        check loaded.descriptor.path == pluginPath
        check loaded.descriptor.uri.len > 0
        check loaded.descriptor.name.len > 0
        check loaded.descriptor.ports.len >= 2
        check loaded.descriptor.params.len > 0
        check loaded.descriptor.hasState

        let firstPort = loaded.descriptor.ports[0]
        check firstPort.kind == pkAudio
        check firstPort.channelCount > 0

        let firstParam = loaded.descriptor.params[0]
        check firstParam.name.len > 0
        check firstParam.maxVal >= firstParam.minVal
        check firstParam.currentVal >= firstParam.minVal
        check firstParam.currentVal <= firstParam.maxVal
        loaded.plugin.close()
