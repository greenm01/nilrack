import std/[options, os, tables, unittest]

import kdl

import ../src/systems/plugin_scan
import ../src/types/[model, plugin_scan_values, plugin_values]

proc scanTestDir(label: string): string =
  result =
    getTempDir() / ("nilrack-plugin-scan-" & $getCurrentProcessId() & "-" & label)
  if dirExists(result):
    removeDir(result)
  createDir(result)

proc exampleDescriptor(path: string): PluginDescriptor =
  PluginDescriptor(
    api: paClap,
    path: path,
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

proc writeScanHelper(path, output: string) =
  writeFile(
    path, "#!/bin/sh\ncat <<'NILRACK_SCAN_EOF'\n" & output & "\nNILRACK_SCAN_EOF\n"
  )
  setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

suite "plugin scan":
  test "formats plugin descriptor scan result as KDL":
    let descriptor = exampleDescriptor("/tmp/example.clap")

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

  test "writes and reads scan cache entries":
    let dir = scanTestDir("read-write")
    defer:
      removeDir(dir)
    let cachePath = dir / "scan-cache.kdl"
    let okNode = scanDescriptorToKdlDoc(exampleDescriptor("/tmp/example.clap"), 123)[0]
    let failedNode = scanFailedEntryToKdlDoc(
      PluginScanFailedEntry(
        path: "/tmp/broken.clap",
        mtime: 456,
        reason: psfrTimeout,
        exitCode: -1,
        timedOut: true,
        error: "scanner timed out",
      )
    )[0]

    var cache: KdlDoc = @[okNode, failedNode]
    check saveScanCache(cachePath, cache)

    let loaded = loadScanCache(cachePath)
    check loaded.len == 2
    check loaded.findCachedScanNode("/tmp/example.clap", 123).isSome
    check loaded.findCachedScanNode("/tmp/broken.clap", 456).isSome

  test "scan cache hit returns ok result without helper":
    let dir = scanTestDir("ok-hit")
    defer:
      removeDir(dir)
    let cachePath = dir / "scan-cache.kdl"
    let pluginPath = dir / "plugin.clap"
    writeFile(pluginPath, "plugin")
    let mtime = pluginMtime(pluginPath)
    var cache = scanDescriptorToKdlDoc(exampleDescriptor(pluginPath), mtime)
    check saveScanCache(cachePath, cache)

    let result = scanPluginWithCache(dir / "missing-helper", pluginPath, cachePath, 100)
    check result.ok
    check result.reason == psfrNone
    check parseKdl(result.output)[0].props["path"].get(string) == pluginPath

  test "scan cache hit returns failed result without helper":
    let dir = scanTestDir("failed-hit")
    defer:
      removeDir(dir)
    let cachePath = dir / "scan-cache.kdl"
    let pluginPath = dir / "plugin.clap"
    writeFile(pluginPath, "plugin")
    let mtime = pluginMtime(pluginPath)
    var cache = scanFailedEntryToKdlDoc(
      PluginScanFailedEntry(
        path: pluginPath,
        mtime: mtime,
        reason: psfrNonZeroExit,
        exitCode: 2,
        timedOut: false,
        error: "scanner exited non-zero",
      )
    )
    check saveScanCache(cachePath, cache)

    let result = scanPluginWithCache(dir / "missing-helper", pluginPath, cachePath, 100)
    check not result.ok
    check result.reason == psfrNonZeroExit
    check result.exitCode == 2
    check result.error == "scanner exited non-zero"

  test "scan cache mtime miss runs helper and updates cache":
    let dir = scanTestDir("mtime-miss")
    defer:
      removeDir(dir)
    let cachePath = dir / "scan-cache.kdl"
    let pluginPath = dir / "plugin.clap"
    writeFile(pluginPath, "plugin")
    let mtime = pluginMtime(pluginPath)
    var cache = scanDescriptorToKdlDoc(exampleDescriptor(pluginPath), mtime - 1)
    check saveScanCache(cachePath, cache)

    let helperPath = dir / "scan-helper"
    writeScanHelper(
      helperPath, scanDescriptorToKdl(exampleDescriptor(pluginPath), mtime)
    )

    let result = scanPluginWithCache(helperPath, pluginPath, cachePath, 1000)
    check result.ok

    let loaded = loadScanCache(cachePath)
    check loaded.findCachedScanNode(pluginPath, mtime).isSome
    check loaded.findCachedScanNode(pluginPath, mtime - 1).isNone

  test "scan cache upsert replaces older entries for the same path":
    let oldNode = scanDescriptorToKdlDoc(exampleDescriptor("/tmp/example.clap"), 1)[0]
    let newNode = scanDescriptorToKdlDoc(exampleDescriptor("/tmp/example.clap"), 2)[0]
    let otherNode = scanDescriptorToKdlDoc(exampleDescriptor("/tmp/other.clap"), 1)[0]
    var cache: KdlDoc = @[oldNode, otherNode]

    cache.upsertScanCacheNode(newNode)

    check cache.len == 2
    check cache.findCachedScanNode("/tmp/example.clap", 1).isNone
    check cache.findCachedScanNode("/tmp/example.clap", 2).isSome
    check cache.findCachedScanNode("/tmp/other.clap", 1).isSome

  test "malformed scan cache falls back to helper":
    let dir = scanTestDir("malformed")
    defer:
      removeDir(dir)
    let cachePath = dir / "scan-cache.kdl"
    let pluginPath = dir / "plugin.clap"
    writeFile(pluginPath, "plugin")
    writeFile(cachePath, "plugin-scan {")
    let mtime = pluginMtime(pluginPath)
    let helperPath = dir / "scan-helper"
    writeScanHelper(
      helperPath, scanDescriptorToKdl(exampleDescriptor(pluginPath), mtime)
    )

    let result = scanPluginWithCache(helperPath, pluginPath, cachePath, 1000)
    check result.ok
    check loadScanCache(cachePath).findCachedScanNode(pluginPath, mtime).isSome

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
