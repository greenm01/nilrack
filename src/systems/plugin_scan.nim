import std/[options, os, osproc, posix, streams, strutils, tables, times]

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

proc failureReasonName(reason: PluginScanFailureReason): string =
  case reason
  of psfrNone: "none"
  of psfrTimeout: "timeout"
  of psfrNonZeroExit: "non-zero-exit"
  of psfrEmptyOutput: "empty-output"
  of psfrMalformedKdl: "malformed-kdl"

proc parseFailureReason(name: string): Option[PluginScanFailureReason] =
  case name
  of "none":
    some(psfrNone)
  of "timeout":
    some(psfrTimeout)
  of "non-zero-exit":
    some(psfrNonZeroExit)
  of "empty-output":
    some(psfrEmptyOutput)
  of "malformed-kdl":
    some(psfrMalformedKdl)
  else:
    none(PluginScanFailureReason)

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

proc prop(key: string, val: int): KdlProp =
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

proc scanNodePathMtime(node: KdlNode, path: var string, mtime: var int64): bool =
  if node.name != "plugin-scan":
    return false
  for key in ["schema", "status", "path", "mtime"]:
    if not node.props.hasKey(key):
      return false
  try:
    if node.props["schema"].get(uint32) != PluginScanSchemaVersion.uint32:
      return false
    path = node.props["path"].get(string)
    mtime = node.props["mtime"].get(int64)
    true
  except CatchableError:
    false

proc scanNodeMatches(node: KdlNode, path: string, mtime: int64): bool =
  var nodePath: string
  var nodeMtime: int64
  node.scanNodePathMtime(nodePath, nodeMtime) and nodePath == path and nodeMtime == mtime

proc scanNodeMatchesPath(node: KdlNode, path: string): bool =
  var nodePath: string
  var nodeMtime: int64
  node.scanNodePathMtime(nodePath, nodeMtime) and nodePath == path

proc failedEntryFromScanResult*(
    path: string, mtime: int64, scanResult: PluginScanProcessResult
): PluginScanFailedEntry =
  PluginScanFailedEntry(
    path: path,
    mtime: mtime,
    reason: scanResult.reason,
    exitCode: scanResult.exitCode,
    timedOut: scanResult.timedOut,
    error: scanResult.error,
  )

proc scanFailedEntryToKdlDoc*(entry: PluginScanFailedEntry): KdlDoc =
  @[
    initKNode(
      "plugin-scan",
      props = props(
        [
          prop("schema", PluginScanSchemaVersion.uint32),
          prop("status", "failed"),
          prop("path", entry.path),
          prop("mtime", entry.mtime),
          prop("reason", entry.reason.failureReasonName()),
          prop("exit-code", entry.exitCode),
          prop("timed-out", entry.timedOut),
          prop("error", entry.error),
        ]
      ),
    )
  ]

proc scanFailedEntryToKdl*(entry: PluginScanFailedEntry): string =
  pretty(scanFailedEntryToKdlDoc(entry))

proc scanFailureToKdlDoc*(
    path: string, mtime: int64, scanResult: PluginScanProcessResult
): KdlDoc =
  scanFailedEntryToKdlDoc(failedEntryFromScanResult(path, mtime, scanResult))

proc scanFailureToKdl*(
    path: string, mtime: int64, scanResult: PluginScanProcessResult
): string =
  pretty(scanFailureToKdlDoc(path, mtime, scanResult))

proc parseScanFailedEntry*(node: KdlNode): Option[PluginScanFailedEntry] =
  if node.name != "plugin-scan":
    return none(PluginScanFailedEntry)
  for key in [
    "schema", "status", "path", "mtime", "reason", "exit-code", "timed-out", "error"
  ]:
    if not node.props.hasKey(key):
      return none(PluginScanFailedEntry)
  try:
    if node.props["schema"].get(uint32) != PluginScanSchemaVersion.uint32:
      return none(PluginScanFailedEntry)
    if node.props["status"].get(string) != "failed":
      return none(PluginScanFailedEntry)
    let reason = parseFailureReason(node.props["reason"].get(string))
    if reason.isNone or reason.get == psfrNone:
      return none(PluginScanFailedEntry)
    some(
      PluginScanFailedEntry(
        path: node.props["path"].get(string),
        mtime: node.props["mtime"].get(int64),
        reason: reason.get,
        exitCode: node.props["exit-code"].get(int),
        timedOut: node.props["timed-out"].get(bool),
        error: node.props["error"].get(string),
      )
    )
  except CatchableError:
    none(PluginScanFailedEntry)

proc parseScanFailedEntry*(doc: KdlDoc): Option[PluginScanFailedEntry] =
  if doc.len != 1:
    return none(PluginScanFailedEntry)
  parseScanFailedEntry(doc[0])

proc scanFailedEntryMatches*(
    entry: PluginScanFailedEntry, path: string, mtime: int64
): bool =
  entry.path == path and entry.mtime == mtime

proc loadScanCache*(cachePath: string): KdlDoc =
  if not fileExists(cachePath):
    return @[]
  try:
    parseKdl(readFile(cachePath))
  except CatchableError:
    @[]

proc findCachedScanNode*(
    cache: KdlDoc, pluginPath: string, mtime: int64
): Option[KdlNode] =
  for node in cache:
    if node.scanNodeMatches(pluginPath, mtime):
      return some(node)
  none(KdlNode)

proc upsertScanCacheNode*(cache: var KdlDoc, node: KdlNode) =
  var nodePath: string
  var nodeMtime: int64
  if not node.scanNodePathMtime(nodePath, nodeMtime):
    return
  var kept: KdlDoc = @[]
  for existing in cache:
    if not existing.scanNodeMatchesPath(nodePath):
      kept.add(existing)
  kept.add(node)
  cache = kept

proc syncParentDir(path: string) =
  let dir = parentDir(path)
  if dir.len == 0:
    return
  let fd = posix.open(dir.cstring, O_RDONLY)
  if fd >= 0:
    discard posix.fsync(fd)
    discard posix.close(fd)

proc writeAll(fd: cint, text: string): bool =
  var written = 0
  while written < text.len:
    let count =
      posix.write(fd, cast[pointer](unsafeAddr text[written]), text.len - written)
    if count <= 0:
      return false
    written += count
  true

proc saveScanCache*(cachePath: string, cache: KdlDoc): bool =
  let dir = parentDir(cachePath)
  if dir.len > 0:
    createDir(dir)

  let tempPath = cachePath & ".tmp"
  let fd = posix.open(tempPath.cstring, O_CREAT or O_WRONLY or O_TRUNC, Mode(0o600))
  if fd < 0:
    return false

  let text = pretty(cache)
  result = writeAll(fd, text)
  if result:
    result = posix.fsync(fd) == 0
  if posix.close(fd) != 0:
    result = false

  if not result:
    discard tryRemoveFile(tempPath)
    return false

  try:
    moveFile(tempPath, cachePath)
    syncParentDir(cachePath)
    result = true
  except OSError:
    discard tryRemoveFile(tempPath)
    result = false

proc cachedNodeToProcessResult(node: KdlNode): Option[PluginScanProcessResult] =
  try:
    if not node.props.hasKey("status"):
      return none(PluginScanProcessResult)
    case node.props["status"].get(string)
    of "ok":
      some(
        PluginScanProcessResult(
          ok: true, reason: psfrNone, exitCode: 0, output: pretty(@[node])
        )
      )
    of "failed":
      let entry = parseScanFailedEntry(node)
      if entry.isNone:
        return none(PluginScanProcessResult)
      some(
        PluginScanProcessResult(
          ok: false,
          reason: entry.get.reason,
          exitCode: entry.get.exitCode,
          timedOut: entry.get.timedOut,
          output: scanFailedEntryToKdl(entry.get),
          error: entry.get.error,
        )
      )
    else:
      none(PluginScanProcessResult)
  except CatchableError:
    none(PluginScanProcessResult)

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

proc updateScanCacheFromResult(
    cachePath: string,
    cache: var KdlDoc,
    pluginPath: string,
    mtime: int64,
    scanResult: PluginScanProcessResult,
) =
  if scanResult.ok:
    try:
      let doc = parseKdl(scanResult.output)
      for node in doc:
        if node.scanNodeMatches(pluginPath, mtime):
          cache.upsertScanCacheNode(node)
          discard saveScanCache(cachePath, cache)
          return
    except CatchableError:
      discard
  else:
    cache.upsertScanCacheNode(
      scanFailedEntryToKdlDoc(failedEntryFromScanResult(pluginPath, mtime, scanResult))[
        0
      ]
    )
    discard saveScanCache(cachePath, cache)

proc scanPluginWithCache*(
    scannerExe, pluginPath, cachePath: string, timeoutMs: int = PluginScanTimeoutMs
): PluginScanProcessResult =
  let mtime = pluginMtime(pluginPath)
  var cache = loadScanCache(cachePath)

  let cached = cache.findCachedScanNode(pluginPath, mtime)
  if cached.isSome:
    let cachedResult = cachedNodeToProcessResult(cached.get)
    if cachedResult.isSome:
      return cachedResult.get

  result = scanPluginWithHelper(scannerExe, pluginPath, timeoutMs)
  updateScanCacheFromResult(cachePath, cache, pluginPath, mtime, result)

proc rescanPluginWithCache*(
    scannerExe, pluginPath, cachePath: string, timeoutMs: int = PluginScanTimeoutMs
): PluginScanProcessResult =
  let mtime = pluginMtime(pluginPath)
  var cache = loadScanCache(cachePath)
  result = scanPluginWithHelper(scannerExe, pluginPath, timeoutMs)
  updateScanCacheFromResult(cachePath, cache, pluginPath, mtime, result)
