import std/[options, os, unittest]

import ../src/plugins/clap_host
import ../src/state/engine
import ../src/types/audio_values

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

    test "activates and processes a mono audio block":
      let loaded = loadClapPlugin(pluginPath)
      check loaded.ok
      if loaded.ok:
        check loaded.plugin.activateClap(48000.0, 1, 64)
        check loaded.plugin.startClapProcessing()

        var input1: array[64, float32]
        var input2: array[64, float32]
        var output1: array[64, float32]
        var output2: array[64, float32]
        for i in 0 .. input1.high:
          input1[i] = (i.float32 / 64.0'f32) * 0.05'f32
          input2[i] = -input1[i]

        check clapProcessAudioBlock(
          loaded.plugin.clapRuntimePointer(),
          addr input1[0],
          addr input2[0],
          addr output1[0],
          addr output2[0],
          64,
          aimMonoLeftToStereo,
        )
        for i in 0 .. output1.high:
          check output1[i] == output2[i]

        loaded.plugin.stopClapProcessing()
        loaded.plugin.deactivateClap()
        loaded.plugin.close()

    test "saves plugin state to a state blob":
      let loaded = loadClapPlugin(pluginPath)
      check loaded.ok
      if loaded.ok:
        check loaded.descriptor.hasState
        var stateRef: StateBlobRef
        check loaded.plugin.saveClapState(stateRef)
        loaded.plugin.close()

    test "restores state into a stopped plugin before applying model params":
      let saved = loadClapPlugin(pluginPath)
      check saved.ok
      if saved.ok:
        var stateRef: StateBlobRef
        check saved.plugin.saveClapState(stateRef)
        saved.plugin.close()

        let restored = loadClapPlugin(pluginPath)
        check restored.ok
        if restored.ok:
          check restored.plugin.loadClapState(stateRef)

          var model = NilrackModel()
          let rackId = model.rackCreate("Restore smoke")
          let nodeId = model.nodeCreate(rackId, nkPlugin, "Plugin")
          let pluginId = model.pluginAttachToNode(
            nodeId,
            paClap,
            pluginPath,
            restored.descriptor.uri,
            restored.descriptor.name,
            hasState = restored.descriptor.hasState,
          )
          let paramId = model.paramCreate(nodeId, "Gain", 0.0, 1.0, 0.25)

          model.pluginSetStateRef(pluginId, stateRef)
          model.paramSetNormalized(paramId, 0.75)

          check model.plugins.entity(pluginId).get.stateRef.data == stateRef.data
          check model.params.entity(paramId).get.currentVal == 0.75
          restored.plugin.close()
