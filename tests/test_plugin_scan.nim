import std/[os, unittest]

import kdl

import ../src/systems/plugin_scan
import ../src/types/[model, plugin_scan_values, plugin_values]

suite "plugin scan":
  test "formats plugin descriptor scan result as KDL":
    let descriptor = PluginDescriptor(
      api: paClap,
      path: "/tmp/example.clap",
      uri: "dev.nilrack.example",
      name: "Example",
      vendor: "niltempus",
      version: "1.0.0",
      description: "test plugin",
      hasState: true,
      ports:
        @[
          PluginPortDescriptor(
            index: 0,
            externalId: 7,
            name: "Audio In",
            kind: pkAudio,
            direction: pdIn,
            channelCount: 2,
            isMain: true,
            portType: "stereo",
          )
        ],
      params:
        @[
          PluginParamDescriptor(
            index: 0,
            externalId: 100,
            name: "Gain",
            modulePath: "Input",
            minVal: 0.0,
            maxVal: 1.0,
            defaultVal: 0.5,
            currentVal: 0.75,
            displayText: "0.75",
            automatable: true,
          )
        ],
    )

    let doc = parseKdl(scanDescriptorToKdl(descriptor, 123))
    check doc.len == 1
    check doc[0].name == "plugin-scan"
    check doc[0].props["status"].get(string) == "ok"
    check doc[0].props["format"].get(string) == "clap"
    check doc[0].props["mtime"].get(int64) == 123
    check doc[0].children.len == 4
    check doc[0].children[0].name == "descriptor"
    check doc[0].children[1].name == "port"
    check doc[0].children[2].name == "param"
    check doc[0].children[3].name == "ui"
    check doc[0].children[0].props["has-state"].get(bool)
    check doc[0].children[1].props["channel-count"].get(uint32) == 2'u32
    check doc[0].children[2].props["current"].get(float64) == 0.75
    check doc[0].children[3].props["generated"].get(bool)

  test "scanner process runner accepts valid KDL output":
    let printfExe = findExe("printf")
    if printfExe.len == 0:
      echo "SKIP: printf not found"
    else:
      let result =
        runPluginScannerProcess(printfExe, ["plugin-scan status=ok\\n"], 1000)
      check result.ok
      check result.reason == psfrNone
      check result.exitCode == 0

  test "scanner process runner classifies process failures":
    let falseExe = findExe("false")
    let trueExe = findExe("true")
    if falseExe.len == 0 or trueExe.len == 0:
      echo "SKIP: true or false not found"
    else:
      let failed = runPluginScannerProcess(falseExe, [], 1000)
      check not failed.ok
      check failed.reason == psfrNonZeroExit

      let empty = runPluginScannerProcess(trueExe, [], 1000)
      check not empty.ok
      check empty.reason == psfrEmptyOutput

  test "scanner process runner classifies malformed output and timeout":
    let printfExe = findExe("printf")
    let sleepExe = findExe("sleep")
    if printfExe.len == 0 or sleepExe.len == 0:
      echo "SKIP: printf or sleep not found"
    else:
      let malformed = runPluginScannerProcess(printfExe, ["plugin-scan {"], 1000)
      check not malformed.ok
      check malformed.reason == psfrMalformedKdl

      let timedOut = runPluginScannerProcess(sleepExe, ["1"], 10)
      check not timedOut.ok
      check timedOut.reason == psfrTimeout
      check timedOut.timedOut
