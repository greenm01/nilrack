import std/[dynlib, os, strformat, strutils]

import plugin_runtime_api
import ../types/audio_values
import ../types/[core, model, plugin_runtime_values, plugin_values]
import clap_api
import clap_host_callbacks

type
  ClapLoadedPlugin* = ref object
    pluginPath*: string
    libraryPath*: string
    module: LibHandle
    entry: ptr ClapPluginEntry
    factory: ptr ClapPluginFactory
    hostBox: ClapHostBox
    plugin: ptr ClapPlugin
    inputChannels: array[2, ptr cfloat]
    outputChannels: array[2, ptr cfloat]
    inputBuffer: ClapAudioBuffer
    outputBuffer: ClapAudioBuffer
    inputEvents: ClapInputEvents
    outputEvents: ClapOutputEvents
    process: ClapProcess
    steadyTime: int64
    entryInitialized: bool
    pluginInitialized: bool
    active: bool
    processing: bool

  ClapLoadResult* = object
    ok*: bool
    error*: string
    plugin*: ClapLoadedPlugin
    descriptor*: PluginDescriptor

  ClapStateWriteContext = object
    data: seq[byte]

  ClapStateReadContext = object
    data: ptr UncheckedArray[byte]
    len: int
    offset: int

proc cstr(value: cstring): string =
  if value.isNil:
    ""
  else:
    $value

proc carrayString[N: static int](value: array[N, char]): string =
  result = ""
  for ch in value:
    if ch == '\0':
      break
    result.add(ch)

proc bitSet(value, bit: uint32): bool =
  (value and bit) != 0

proc clapLibraryPath*(pluginPath: string): string =
  result = pluginPath
  when defined(windows):
    discard
  else:
    if dirExists(pluginPath):
      let base = splitFile(pluginPath).name
      let libName =
        if base.endsWith(".clap"):
          base[0 ..< base.len - ".clap".len]
        else:
          base
      result = pluginPath / "Contents" / "MacOS" / libName

proc fail(error: string): ClapLoadResult =
  ClapLoadResult(ok: false, error: error)

proc emptyEventsSize(list: ptr ClapInputEvents): uint32 {.cdecl.} =
  discard list
  0

proc emptyEventsGet(
    list: ptr ClapInputEvents, index: uint32
): ptr ClapEventHeader {.cdecl.} =
  discard list
  discard index
  nil

proc dropOutputEvent(
    list: ptr ClapOutputEvents, event: ptr ClapEventHeader
): bool {.cdecl.} =
  discard list
  discard event
  false

proc clapStateWrite(
    stream: ptr ClapOStream, buffer: pointer, size: uint64
): int64 {.cdecl, raises: [].} =
  if stream.isNil or stream.ctx.isNil or buffer.isNil:
    return -1
  try:
    let count = size.int
    let source = cast[ptr UncheckedArray[byte]](buffer)
    let ctx = cast[ptr ClapStateWriteContext](stream.ctx)
    for index in 0 ..< count:
      ctx.data.add(source[index])
    int64(count)
  except Exception:
    -1

proc clapStateRead(
    stream: ptr ClapIStream, buffer: pointer, size: uint64
): int64 {.cdecl, raises: [].} =
  if stream.isNil or stream.ctx.isNil or buffer.isNil:
    return -1
  let ctx = cast[ptr ClapStateReadContext](stream.ctx)
  if ctx.offset >= ctx.len:
    return 0
  let requested =
    if size > uint64(high(int)):
      high(int)
    else:
      size.int
  let available = ctx.len - ctx.offset
  let count = if requested < available: requested else: available
  if count > 0:
    copyMem(buffer, addr ctx.data[ctx.offset], count)
    ctx.offset += count
  int64(count)

proc initProcessStorage(loaded: ClapLoadedPlugin) =
  loaded.inputBuffer = ClapAudioBuffer(
    data32: cast[ptr ptr cfloat](addr loaded.inputChannels[0]),
    data64: nil,
    latency: 0,
    constantMask: 0,
  )
  loaded.outputBuffer = ClapAudioBuffer(
    data32: cast[ptr ptr cfloat](addr loaded.outputChannels[0]),
    data64: nil,
    latency: 0,
    constantMask: 0,
  )
  loaded.inputEvents =
    ClapInputEvents(ctx: nil, size: emptyEventsSize, get: emptyEventsGet)
  loaded.outputEvents = ClapOutputEvents(ctx: nil, tryPush: dropOutputEvent)
  loaded.process = ClapProcess(
    steadyTime: 0,
    framesCount: 0,
    transport: nil,
    audioInputs: addr loaded.inputBuffer,
    audioOutputs: addr loaded.outputBuffer,
    audioInputsCount: 1,
    audioOutputsCount: 1,
    inEvents: addr loaded.inputEvents,
    outEvents: addr loaded.outputEvents,
  )

proc close*(loaded: ClapLoadedPlugin) =
  if loaded.isNil:
    return
  if loaded.processing and not loaded.plugin.isNil:
    loaded.plugin.stopProcessing(loaded.plugin)
    loaded.processing = false
  if loaded.active and not loaded.plugin.isNil:
    loaded.plugin.deactivate(loaded.plugin)
    loaded.active = false
  if not loaded.plugin.isNil:
    loaded.plugin.destroy(loaded.plugin)
    loaded.plugin = nil
    loaded.pluginInitialized = false
  if loaded.entryInitialized and not loaded.entry.isNil:
    loaded.entry.deinit()
    loaded.entryInitialized = false
  if loaded.module != nil:
    unloadLib(loaded.module)
    loaded.module = nil
  loaded.entry = nil
  loaded.factory = nil

proc popClapHostEvent*(
    loaded: ClapLoadedPlugin, event: var PluginEventThreadEvent
): bool =
  if loaded.isNil or loaded.hostBox.isNil:
    return false
  loaded.hostBox.popClapHostBoxEvent(event)

proc bindClapPluginId*(loaded: ClapLoadedPlugin, pluginId: PluginId) =
  if loaded.isNil or loaded.hostBox.isNil:
    return
  loaded.hostBox.bindClapHostPluginId(pluginId)

proc descriptorFromClap(
    pluginPath: string, desc: ptr ClapPluginDescriptor
): PluginDescriptor =
  PluginDescriptor(
    api: paClap,
    path: pluginPath,
    uri: cstr(desc.id),
    name: cstr(desc.name),
    vendor: cstr(desc.vendor),
    version: cstr(desc.version),
    description: cstr(desc.description),
  )

proc queryAudioPorts(plugin: ptr ClapPlugin, descriptor: var PluginDescriptor) =
  let ext = cast[ptr ClapPluginAudioPorts](plugin.getExtension(
    plugin, ClapExtAudioPorts.cstring
  ))
  if ext.isNil:
    return

  for isInput in [true, false]:
    let count = ext.count(plugin, isInput)
    for index in 0'u32 ..< count:
      var info: ClapAudioPortInfo
      if not ext.get(plugin, index, isInput, addr info):
        continue
      descriptor.ports.add(
        PluginPortDescriptor(
          index: index,
          externalId: info.id,
          name: carrayString(info.name),
          kind: pkAudio,
          direction: (if isInput: pdIn else: pdOut),
          channelCount: info.channelCount,
          isMain: bitSet(info.flags, ClapAudioPortIsMain),
          portType: cstr(info.portType),
        )
      )

proc queryParams(plugin: ptr ClapPlugin, descriptor: var PluginDescriptor) =
  let ext =
    cast[ptr ClapPluginParams](plugin.getExtension(plugin, ClapExtParams.cstring))
  if ext.isNil:
    return

  let count = ext.count(plugin)
  for index in 0'u32 ..< count:
    var info: ClapParamInfo
    if not ext.getInfo(plugin, index, addr info):
      continue
    var current = info.defaultValue
    discard ext.getValue(plugin, info.id, addr current)

    var textBuf: array[128, char]
    var display = ""
    if not ext.valueToText.isNil and
        ext.valueToText(
          plugin, info.id, current, cast[cstring](addr textBuf[0]), uint32(textBuf.len)
        ):
      display = carrayString(textBuf)

    descriptor.params.add(
      PluginParamDescriptor(
        index: index,
        externalId: info.id,
        name: carrayString(info.name),
        modulePath: carrayString(info.module),
        minVal: info.minValue,
        maxVal: info.maxValue,
        defaultVal: info.defaultValue,
        currentVal: current,
        displayText: display,
        stepped: bitSet(info.flags, ClapParamIsStepped),
        hidden: bitSet(info.flags, ClapParamIsHidden),
        readonly: bitSet(info.flags, ClapParamIsReadonly),
        bypass: bitSet(info.flags, ClapParamIsBypass),
        automatable: bitSet(info.flags, ClapParamIsAutomatable),
      )
    )

proc queryState(plugin: ptr ClapPlugin, descriptor: var PluginDescriptor) =
  descriptor.hasState =
    not cast[ptr ClapPluginState](plugin.getExtension(plugin, ClapExtState.cstring)).isNil

proc stateExtension(
    loaded: ClapLoadedPlugin
): ptr ClapPluginState {.gcsafe, raises: [].} =
  if loaded.isNil or loaded.plugin.isNil:
    return nil
  cast[ptr ClapPluginState](loaded.plugin.getExtension(
    loaded.plugin, ClapExtState.cstring
  ))

proc saveClapState*(
    loaded: ClapLoadedPlugin, stateRef: var StateBlobRef
): bool {.gcsafe, raises: [].} =
  try:
    let ext = loaded.stateExtension()
    if ext.isNil or ext.save.isNil:
      return false

    var ctx: ClapStateWriteContext
    var stream = ClapOStream(ctx: addr ctx, write: clapStateWrite)
    if not ext.save(loaded.plugin, addr stream):
      return false

    stateRef.data = ctx.data
    true
  except Exception:
    return false

proc loadClapState*(
    loaded: ClapLoadedPlugin, stateRef: StateBlobRef
): bool {.gcsafe, raises: [].} =
  try:
    let ext = loaded.stateExtension()
    if ext.isNil or ext.load.isNil or loaded.processing:
      return false

    var ctx = ClapStateReadContext(len: stateRef.data.len)
    if stateRef.data.len > 0:
      ctx.data = cast[ptr UncheckedArray[byte]](unsafeAddr stateRef.data[0])
    var stream = ClapIStream(ctx: addr ctx, read: clapStateRead)
    ext.load(loaded.plugin, addr stream)
  except Exception:
    false

proc activateClap*(
    loaded: ClapLoadedPlugin, sampleRate: float64, minFrames, maxFrames: uint32
): bool =
  if loaded.isNil or loaded.plugin.isNil or loaded.plugin.activate.isNil:
    return false
  if loaded.active:
    return true
  if loaded.plugin.activate(loaded.plugin, sampleRate, minFrames, maxFrames):
    loaded.active = true
    return true
  false

proc startClapProcessing*(loaded: ClapLoadedPlugin): bool =
  if loaded.isNil or loaded.plugin.isNil or loaded.plugin.startProcessing.isNil:
    return false
  if loaded.processing:
    return true
  if not loaded.active:
    return false
  if loaded.plugin.startProcessing(loaded.plugin):
    loaded.processing = true
    return true
  false

proc stopClapProcessing*(loaded: ClapLoadedPlugin) =
  if loaded.isNil or loaded.plugin.isNil or not loaded.processing:
    return
  loaded.plugin.stopProcessing(loaded.plugin)
  loaded.processing = false

proc deactivateClap*(loaded: ClapLoadedPlugin) =
  if loaded.isNil or loaded.plugin.isNil or not loaded.active:
    return
  if loaded.processing:
    loaded.stopClapProcessing()
  loaded.plugin.deactivate(loaded.plugin)
  loaded.active = false

proc clapRuntimePointer*(loaded: ClapLoadedPlugin): pointer =
  cast[pointer](loaded)

proc clapRuntimeActivate(
    runtime: pointer, sampleRate: float64, minFrames, maxFrames: uint32
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  let loaded = cast[ClapLoadedPlugin](runtime)
  if loaded.isNil:
    return prsFailed
  try:
    if loaded.activateClap(sampleRate, minFrames, maxFrames): prsOk else: prsFailed
  except CatchableError:
    prsFailed

proc clapRuntimeDeactivate(
    runtime: pointer
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  let loaded = cast[ClapLoadedPlugin](runtime)
  if loaded.isNil:
    return prsFailed
  try:
    loaded.deactivateClap()
    prsOk
  except CatchableError:
    prsFailed

proc clapRuntimeStartProcessing(
    runtime: pointer
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  let loaded = cast[ClapLoadedPlugin](runtime)
  if loaded.isNil:
    return prsFailed
  try:
    if loaded.startClapProcessing(): prsOk else: prsFailed
  except CatchableError:
    prsFailed

proc clapRuntimeStopProcessing(
    runtime: pointer
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  let loaded = cast[ClapLoadedPlugin](runtime)
  if loaded.isNil:
    return prsFailed
  try:
    loaded.stopClapProcessing()
    prsOk
  except CatchableError:
    prsFailed

proc clapProcessAudioBlock*(
  runtime: pointer, in1, in2, out1, out2: pointer, nframes: uint32, mode: AudioIoMode
): bool {.gcsafe, raises: [].}

proc busChannel(bus: PluginAudioBus, index: uint32): pointer =
  if bus.channels.isNil or index >= bus.channelCount:
    return nil
  bus.channels[index]

proc clapRuntimeProcess(
    runtime: pointer, context: ptr ProcessContext
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  if context.isNil or context.audioInputBusCount == 0 or context.audioOutputBusCount == 0:
    return prsBypass

  let input = context.audioInputs[0]
  let output = context.audioOutputs[0]
  let mode =
    if input.channelCount == 1 and output.channelCount == 1:
      aimMonoLeftToStereo
    elif input.channelCount >= 2 and output.channelCount >= 2:
      aimStereo
    else:
      aimBypass
  if mode == aimBypass:
    return prsBypass

  let in1 = input.busChannel(0)
  let in2 =
    if input.channelCount >= 2:
      input.busChannel(1)
    else:
      in1
  let out1 = output.busChannel(0)
  let out2 =
    if output.channelCount >= 2:
      output.busChannel(1)
    else:
      out1
  if in1.isNil or in2.isNil or out1.isNil or out2.isNil:
    return prsFailed
  if clapProcessAudioBlock(runtime, in1, in2, out1, out2, context.frames, mode):
    prsOk
  else:
    prsFailed

proc clapRuntimeSaveState(
    runtime: pointer, writer: PluginRuntimeStateWriteProc, writerCtx: pointer
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  let loaded = cast[ClapLoadedPlugin](runtime)
  if loaded.isNil or writer.isNil:
    return prsFailed
  try:
    var stateRef: StateBlobRef
    if not loaded.saveClapState(stateRef):
      return prsFailed
    if stateRef.data.len == 0:
      if writer(writerCtx, nil, 0): prsOk else: prsFailed
    elif writer(
      writerCtx, cast[pointer](unsafeAddr stateRef.data[0]), stateRef.data.len.uint64
    ):
      prsOk
    else:
      prsFailed
  except CatchableError:
    prsFailed

proc clapRuntimeLoadState(
    runtime: pointer, data: pointer, byteCount: uint64
): PluginRuntimeStatus {.nimcall, gcsafe, raises: [].} =
  let loaded = cast[ClapLoadedPlugin](runtime)
  if loaded.isNil or (data.isNil and byteCount > 0):
    return prsFailed
  try:
    if byteCount > high(int).uint64:
      return prsFailed
    var stateRef: StateBlobRef
    if byteCount > 0:
      stateRef.data.setLen(byteCount.int)
      copyMem(addr stateRef.data[0], data, byteCount.int)
    if loaded.loadClapState(stateRef): prsOk else: prsFailed
  except CatchableError:
    prsFailed

proc clapRuntimeDestroy(runtime: pointer) {.nimcall, gcsafe, raises: [].} =
  let loaded = cast[ClapLoadedPlugin](runtime)
  if loaded.isNil:
    return
  try:
    loaded.close()
  except CatchableError:
    discard

var clapRuntimeOps = PluginRuntimeOps(
  activate: clapRuntimeActivate,
  deactivate: clapRuntimeDeactivate,
  startProcessing: clapRuntimeStartProcessing,
  stopProcessing: clapRuntimeStopProcessing,
  process: clapRuntimeProcess,
  saveState: clapRuntimeSaveState,
  loadState: clapRuntimeLoadState,
  destroy: clapRuntimeDestroy,
)

proc clapPluginRuntimeRef*(
    loaded: ClapLoadedPlugin, pluginId: PluginId
): PluginRuntimeRef =
  PluginRuntimeRef(
    pluginId: pluginId,
    runtime: loaded.clapRuntimePointer(),
    ops: cast[pointer](addr clapRuntimeOps),
  )

proc processStatusOk(status: int32): bool =
  status != ClapProcessError

proc clapProcessAudioBlock*(
    runtime: pointer, in1, in2, out1, out2: pointer, nframes: uint32, mode: AudioIoMode
): bool {.gcsafe, raises: [].} =
  let loaded = cast[ClapLoadedPlugin](runtime)
  if loaded.isNil or loaded.plugin.isNil or not loaded.processing or
      loaded.plugin.process.isNil:
    return false

  case mode
  of aimMonoLeftToStereo:
    loaded.inputChannels[0] = cast[ptr cfloat](in1)
    loaded.outputChannels[0] = cast[ptr cfloat](out1)
    loaded.inputBuffer.channelCount = 1
    loaded.outputBuffer.channelCount = 1
    loaded.process.audioInputsCount = 1
    loaded.process.audioOutputsCount = 1
  of aimStereo:
    loaded.inputChannels[0] = cast[ptr cfloat](in1)
    loaded.inputChannels[1] = cast[ptr cfloat](in2)
    loaded.outputChannels[0] = cast[ptr cfloat](out1)
    loaded.outputChannels[1] = cast[ptr cfloat](out2)
    loaded.inputBuffer.channelCount = 2
    loaded.outputBuffer.channelCount = 2
    loaded.process.audioInputsCount = 1
    loaded.process.audioOutputsCount = 1
  of aimBypass:
    return false

  loaded.process.steadyTime = loaded.steadyTime
  loaded.process.framesCount = nframes
  let status = loaded.plugin.process(loaded.plugin, addr loaded.process)
  if not processStatusOk(status):
    return false

  loaded.steadyTime += nframes.int64
  if mode == aimMonoLeftToStereo:
    copyMem(out2, out1, nframes.int * sizeof(float32))
  true

proc loadClapPlugin*(pluginPath: string): ClapLoadResult =
  let libraryPath = clapLibraryPath(pluginPath)
  if not fileExists(libraryPath):
    return fail("CLAP library does not exist: " & libraryPath)

  var loaded = ClapLoadedPlugin(pluginPath: pluginPath, libraryPath: libraryPath)
  loaded.module = loadLib(libraryPath)
  if loaded.module == nil:
    return fail("failed to load CLAP library: " & libraryPath)

  try:
    loaded.entry = cast[ptr ClapPluginEntry](symAddr(loaded.module, "clap_entry"))
    if loaded.entry.isNil:
      loaded.close()
      return fail("missing clap_entry")
    if not versionCompatible(loaded.entry.clapVersion):
      loaded.close()
      return fail(
        &"unsupported CLAP version {loaded.entry.clapVersion.major}.{loaded.entry.clapVersion.minor}.{loaded.entry.clapVersion.revision}"
      )
    if loaded.entry.init.isNil or not loaded.entry.init(pluginPath.cstring):
      loaded.close()
      return fail("clap_entry.init failed")
    loaded.entryInitialized = true

    loaded.factory =
      cast[ptr ClapPluginFactory](loaded.entry.getFactory(ClapPluginFactoryId.cstring))
    if loaded.factory.isNil:
      loaded.close()
      return fail("missing CLAP plugin factory")

    if loaded.factory.getPluginCount(loaded.factory) == 0:
      loaded.close()
      return fail("CLAP plugin factory returned no plugins")

    let desc = loaded.factory.getPluginDescriptor(loaded.factory, 0)
    if desc.isNil or desc.id.isNil or desc.name.isNil:
      loaded.close()
      return fail("missing CLAP plugin descriptor")

    loaded.hostBox = newClapHostBox()
    loaded.plugin =
      loaded.factory.createPlugin(loaded.factory, addr loaded.hostBox.host, desc.id)
    if loaded.plugin.isNil:
      loaded.close()
      return fail("CLAP create_plugin failed")
    if loaded.plugin.init.isNil or not loaded.plugin.init(loaded.plugin):
      loaded.close()
      return fail("CLAP plugin init failed")
    loaded.pluginInitialized = true
    loaded.initProcessStorage()

    var descriptor = descriptorFromClap(pluginPath, desc)
    queryAudioPorts(loaded.plugin, descriptor)
    queryParams(loaded.plugin, descriptor)
    queryState(loaded.plugin, descriptor)

    ClapLoadResult(ok: true, plugin: loaded, descriptor: descriptor)
  except CatchableError as e:
    loaded.close()
    fail("CLAP load failed: " & e.msg)
