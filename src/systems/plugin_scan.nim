import std/[os, osproc, streams, strutils, tables, times]

import kdl

import ../types/[model, plugin_scan_values, plugin_values]

const PluginScanSchemaVersion* = 1

proc pluginApiName(api: PluginApi): string =
  case api
  of paClap: "clap"
  of paLv2: "lv2"
  of paVst3: "vst3"

proc portKindName(kind: PortKind): string =
  case kind
  of pkAudio: "audio"
  of pkMidi: "midi"
  of pkCv: "cv"

proc portDirectionName(direction: PortDirection): string =
  case direction
  of pdIn: "in"
  of pdOut: "out"

proc props(pairs: openArray[KdlProp]): Table[string, KdlVal] =
  result = initTable[string, KdlVal](pairs.len)
  for pair in pairs:
    result[pair.key] = pair.val

proc prop(key: string, val: string): KdlProp =
  (key: key, val: initKVal(val))

proc prop(key: string, val: bool): KdlProp =
  (key: key, val: initKVal(val))

proc prop(key: string, val: uint32): KdlProp =
  (key: key, val: initKVal(val))

proc prop(key: string, val: int64): KdlProp =
  (key: key, val: initKVal(val))

proc prop(key: string, val: float64): KdlProp =
  (key: key, val: initKVal(val))

proc scanDescriptorToKdlDoc*(descriptor: PluginDescriptor, mtime: int64 = 0): KdlDoc =
  var children: seq[KdlNode]
  children.add(
    initKNode(
      "descriptor",
      props = props(
        [
          prop("api", descriptor.api.pluginApiName()),
          prop("uri", descriptor.uri),
          prop("name", descriptor.name),
          prop("vendor", descriptor.vendor),
          prop("version", descriptor.version),
          prop("description", descriptor.description),
          prop("has-state", descriptor.hasState),
        ]
      ),
    )
  )

  for port in descriptor.ports:
    children.add(
      initKNode(
        "port",
        props = props(
          [
            prop("index", port.index),
            prop("external-id", port.externalId),
            prop("name", port.name),
            prop("kind", port.kind.portKindName()),
            prop("direction", port.direction.portDirectionName()),
            prop("channel-count", port.channelCount),
            prop("main", port.isMain),
            prop("port-type", port.portType),
          ]
        ),
      )
    )

  for param in descriptor.params:
    children.add(
      initKNode(
        "param",
        props = props(
          [
            prop("index", param.index),
            prop("external-id", param.externalId),
            prop("name", param.name),
            prop("module", param.modulePath),
            prop("min", param.minVal),
            prop("max", param.maxVal),
            prop("default", param.defaultVal),
            prop("current", param.currentVal),
            prop("display", param.displayText),
            prop("stepped", param.stepped),
            prop("hidden", param.hidden),
            prop("readonly", param.readonly),
            prop("bypass", param.bypass),
            prop("automatable", param.automatable),
          ]
        ),
      )
    )

  children.add(
    initKNode(
      "ui",
      props = props(
        [
          prop("generated", true),
          prop("native-wayland", false),
          prop("xwayland", false),
        ]
      ),
    )
  )

  @[
    initKNode(
      "plugin-scan",
      props = props(
        [
          prop("schema", PluginScanSchemaVersion.uint32),
          prop("status", "ok"),
          prop("path", descriptor.path),
          prop("mtime", mtime),
          prop("format", descriptor.api.pluginApiName()),
        ]
      ),
      children = children,
    )
  ]

proc scanDescriptorToKdl*(descriptor: PluginDescriptor, mtime: int64 = 0): string =
  pretty(scanDescriptorToKdlDoc(descriptor, mtime))

proc pluginMtime*(path: string): int64 =
  if not fileExists(path) and not dirExists(path):
    return 0
  getLastModificationTime(path).toUnix()

proc failure(
    reason: PluginScanFailureReason, exitCode: int, output, error: string
): PluginScanProcessResult =
  PluginScanProcessResult(
    ok: false,
    reason: reason,
    exitCode: exitCode,
    timedOut: reason == psfrTimeout,
    output: output,
    error: error,
  )

proc validateScannerOutput(output: string, exitCode: int): PluginScanProcessResult =
  if exitCode != 0:
    return failure(psfrNonZeroExit, exitCode, output, "scanner exited non-zero")
  if output.strip().len == 0:
    return failure(psfrEmptyOutput, exitCode, output, "scanner produced no output")
  try:
    discard parseKdl(output)
  except CatchableError as err:
    return failure(psfrMalformedKdl, exitCode, output, err.msg)
  PluginScanProcessResult(
    ok: true, reason: psfrNone, exitCode: exitCode, output: output
  )

proc runPluginScannerProcess*(
    scannerExe: string, args: openArray[string], timeoutMs: int = PluginScanTimeoutMs
): PluginScanProcessResult =
  var process: Process
  try:
    process =
      startProcess(scannerExe, args = args, options = {poStdErrToStdOut, poUsePath})
  except CatchableError as err:
    return failure(psfrNonZeroExit, -1, "", err.msg)

  var elapsedMs = 0
  var exitCode = process.peekExitCode()
  while exitCode < 0 and elapsedMs < timeoutMs:
    sleep(10)
    elapsedMs += 10
    exitCode = process.peekExitCode()

  if exitCode < 0:
    process.terminate()
    sleep(20)
    exitCode = process.peekExitCode()
    if exitCode < 0:
      process.kill()
      exitCode = process.peekExitCode()
    let output = process.outputStream.readAll()
    process.close()
    return failure(psfrTimeout, exitCode, output, "scanner timed out")

  let output = process.outputStream.readAll()
  process.close()
  validateScannerOutput(output, exitCode)

proc scanPluginWithHelper*(
    scannerExe, pluginPath: string, timeoutMs: int = PluginScanTimeoutMs
): PluginScanProcessResult =
  runPluginScannerProcess(scannerExe, ["--scan-plugin", pluginPath], timeoutMs)
