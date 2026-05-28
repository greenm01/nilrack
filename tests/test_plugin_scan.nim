import std/[options, os, tables, unittest]

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

  test "formats scanner failure result with typed reason":
    let failure = PluginScanProcessResult(
      ok: false,
      reason: psfrTimeout,
      exitCode: -1,
      timedOut: true,
      error: "scanner timed out",
    )

    let doc = parseKdl(scanFailureToKdl("/tmp/broken.clap", 456, failure))
    check doc.len == 1
    check doc[0].name == "plugin-scan"
    check doc[0].props["status"].get(string) == "failed"
    check doc[0].props["path"].get(string) == "/tmp/broken.clap"
    check doc[0].props["mtime"].get(int64) == 456
    check doc[0].props["reason"].get(string) == "timeout"
    check doc[0].props["exit-code"].get(int) == -1
    check doc[0].props["timed-out"].get(bool)
    check doc[0].props["error"].get(string) == "scanner timed out"

  test "round-trips failed scan cache entries":
    let cases = [
      (
        reason: psfrTimeout,
        reasonName: "timeout",
        exitCode: -1,
        timedOut: true,
        error: "scanner timed out",
      ),
      (
        reason: psfrNonZeroExit,
        reasonName: "non-zero-exit",
        exitCode: 2,
        timedOut: false,
        error: "scanner exited non-zero",
      ),
      (
        reason: psfrEmptyOutput,
        reasonName: "empty-output",
        exitCode: 0,
        timedOut: false,
        error: "scanner produced no output",
      ),
      (
        reason: psfrMalformedKdl,
        reasonName: "malformed-kdl",
        exitCode: 0,
        timedOut: false,
        error: "expected node",
      ),
    ]

    for item in cases:
      let entry = PluginScanFailedEntry(
        path: "/tmp/broken.clap",
        mtime: 789,
        reason: item.reason,
        exitCode: item.exitCode,
        timedOut: item.timedOut,
        error: item.error,
      )

      let doc = parseKdl(scanFailedEntryToKdl(entry))
      check doc[0].props["reason"].get(string) == item.reasonName

      let parsed = parseScanFailedEntry(doc)
      check parsed.isSome
      check parsed.get == entry

  test "builds failed cache entries from process results":
    let result = PluginScanProcessResult(
      ok: false,
      reason: psfrMalformedKdl,
      exitCode: 0,
      timedOut: false,
      output: "plugin-scan {",
      error: "parse failed",
    )

    let entry = failedEntryFromScanResult("/tmp/broken.clap", 123, result)
    check entry.path == "/tmp/broken.clap"
    check entry.mtime == 123
    check entry.reason == psfrMalformedKdl
    check entry.exitCode == 0
    check not entry.timedOut
    check entry.error == "parse failed"

  test "rejects invalid failed scan cache nodes":
    let baseEntry = PluginScanFailedEntry(
      path: "/tmp/a.clap",
      mtime: 1,
      reason: psfrTimeout,
      exitCode: 1,
      timedOut: false,
      error: "failed",
    )

    var okNode = scanFailedEntryToKdlDoc(baseEntry)
    okNode[0].props["status"] = initKVal("ok")
    check parseScanFailedEntry(okNode).isNone

    var missingReason = scanFailedEntryToKdlDoc(baseEntry)
    missingReason[0].props.del("reason")
    check parseScanFailedEntry(missingReason).isNone

    var unsupportedSchema = scanFailedEntryToKdlDoc(baseEntry)
    unsupportedSchema[0].props["schema"] = initKVal(PluginScanSchemaVersion + 1)
    check parseScanFailedEntry(unsupportedSchema).isNone

    var unknownReason = scanFailedEntryToKdlDoc(baseEntry)
    unknownReason[0].props["reason"] = initKVal("unknown")
    check parseScanFailedEntry(unknownReason).isNone

    var noneReason = scanFailedEntryToKdlDoc(baseEntry)
    noneReason[0].props["reason"] = initKVal("none")
    check parseScanFailedEntry(noneReason).isNone

  test "matches failed scan cache entries by path and mtime":
    let entry = PluginScanFailedEntry(
      path: "/tmp/broken.clap",
      mtime: 456,
      reason: psfrTimeout,
      exitCode: -1,
      timedOut: true,
      error: "scanner timed out",
    )

    check entry.scanFailedEntryMatches("/tmp/broken.clap", 456)
    check not entry.scanFailedEntryMatches("/tmp/other.clap", 456)
    check not entry.scanFailedEntryMatches("/tmp/broken.clap", 457)

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
