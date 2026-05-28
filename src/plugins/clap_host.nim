import std/[dynlib, os, strformat, strutils]

import ../types/audio_values
import ../types/[core, model, plugin_runtime_values, plugin_values]
import clap_api
import host_callbacks
import plugin_event_thread_queue

type
  ClapHostRuntime = object
    callbacks: PluginHostCallbackFlags
    eventQueue: PluginEventThreadQueue
    nextTimerId: uint32
    fdSupport: ClapHostPosixFdSupport
    timerSupport: ClapHostTimerSupport

  ClapHostBox = ref object
    runtime: ClapHostRuntime
    host: ClapHost

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

proc hostRuntime(host: ptr ClapHost): ptr ClapHostRuntime =
  if host.isNil or host.hostData.isNil:
    return nil
  cast[ptr ClapHostRuntime](host.hostData)

proc hostGetExtension(host: ptr ClapHost, extensionId: cstring): pointer {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil or extensionId.isNil:
    return nil
  let id = $extensionId
  if id == ClapExtPosixFdSupport:
    return addr runtime.fdSupport
  if id == ClapExtTimerSupport:
    return addr runtime.timerSupport
  nil

proc hostRequestRestart(host: ptr ClapHost) {.cdecl.} =
  let runtime = hostRuntime(host)
  if not runtime.isNil:
    runtime.callbacks.markPluginHostCallback(phcfRestart)

proc hostRequestProcess(host: ptr ClapHost) {.cdecl.} =
  let runtime = hostRuntime(host)
  if not runtime.isNil:
    runtime.callbacks.markPluginHostCallback(phcfProcess)

proc hostRequestCallback(host: ptr ClapHost) {.cdecl.} =
  let runtime = hostRuntime(host)
  if not runtime.isNil:
    runtime.callbacks.markPluginHostCallback(phcfCallback)

proc hostRegisterFd(host: ptr ClapHost, fd: cint, flags: uint32): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil:
    return false
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapFdRegister, pluginId: NullPluginId, fd: fd.int32, fdFlags: flags
    )
  )

proc hostModifyFd(host: ptr ClapHost, fd: cint, flags: uint32): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil:
    return false
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapFdModify, pluginId: NullPluginId, fd: fd.int32, fdFlags: flags
    )
  )

proc hostUnregisterFd(host: ptr ClapHost, fd: cint): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil:
    return false
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapFdUnregister, pluginId: NullPluginId, fd: fd.int32
    )
  )

proc hostRegisterTimer(
    host: ptr ClapHost, periodMs: uint32, timerId: ptr ClapId
): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil or timerId.isNil:
    return false
  inc runtime.nextTimerId
  timerId[] = runtime.nextTimerId
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapTimerRegister,
      pluginId: NullPluginId,
      timerId: timerId[],
      periodMs: periodMs,
    )
  )

proc hostUnregisterTimer(host: ptr ClapHost, timerId: ClapId): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil:
    return false
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapTimerUnregister, pluginId: NullPluginId, timerId: timerId
    )
  )

proc newHostBox(): ClapHostBox =
  result = ClapHostBox()
  result.runtime.callbacks.initPluginHostCallbackFlags()
  result.runtime.fdSupport = ClapHostPosixFdSupport(
    registerFd: hostRegisterFd, modifyFd: hostModifyFd, unregisterFd: hostUnregisterFd
  )
  result.runtime.timerSupport = ClapHostTimerSupport(
    registerTimer: hostRegisterTimer, unregisterTimer: hostUnregisterTimer
  )
  result.host = ClapHost(
    clapVersion: clapVersion(),
    hostData: addr result.runtime,
    name: "nilrack",
    vendor: "niltempus",
    url: "",
    version: "0.1.0",
    getExtension: hostGetExtension,
    requestRestart: hostRequestRestart,
    requestProcess: hostRequestProcess,
    requestCallback: hostRequestCallback,
  )

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
  loaded.hostBox.runtime.eventQueue.dequeuePluginEventThreadEvent(event)

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

proc processStatusOk(status: int32): bool =
  status != ClapProcessError

proc clapProcessAudioBlock*(
    runtime: pointer, in1, in2, out1, out2: pointer, nframes: uint32, mode: AudioIoMode
): bool =
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

    loaded.hostBox = newHostBox()
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
