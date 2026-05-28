const
  ClapVersionMajor* = 1'u32
  ClapVersionMinor* = 2'u32
  ClapVersionRevision* = 7'u32
  ClapNameSize* = 256
  ClapPathSize* = 1024
  ClapInvalidId* = high(uint32)

  ClapPluginFactoryId* = "clap.plugin-factory"
  ClapExtAudioPorts* = "clap.audio-ports"
  ClapExtParams* = "clap.params"
  ClapExtState* = "clap.state"
  ClapExtAudioPortsConfig* = "clap.audio-ports-config"
  ClapPortMono* = "mono"
  ClapPortStereo* = "stereo"

  ClapAudioPortIsMain* = 1'u32 shl 0

  ClapParamIsStepped* = 1'u32 shl 0
  ClapParamIsHidden* = 1'u32 shl 2
  ClapParamIsReadonly* = 1'u32 shl 3
  ClapParamIsBypass* = 1'u32 shl 4
  ClapParamIsAutomatable* = 1'u32 shl 5
  ClapParamIsEnum* = 1'u32 shl 16

  ClapCoreEventSpaceId* = 0'u16
  ClapEventParamValueType* = 5'u16
  ClapEventIsLive* = 1'u32 shl 0

type
  ClapId* = uint32

  ClapVersion* {.bycopy.} = object
    major*: uint32
    minor*: uint32
    revision*: uint32

  ClapPluginEntry* {.bycopy.} = object
    clapVersion*: ClapVersion
    init*: proc(pluginPath: cstring): bool {.cdecl.}
    deinit*: proc() {.cdecl.}
    getFactory*: proc(factoryId: cstring): pointer {.cdecl.}

  ClapPluginDescriptor* {.bycopy.} = object
    clapVersion*: ClapVersion
    id*: cstring
    name*: cstring
    vendor*: cstring
    url*: cstring
    manualUrl*: cstring
    supportUrl*: cstring
    version*: cstring
    description*: cstring
    features*: ptr UncheckedArray[cstring]

  ClapHost* {.bycopy.} = object
    clapVersion*: ClapVersion
    hostData*: pointer
    name*: cstring
    vendor*: cstring
    url*: cstring
    version*: cstring
    getExtension*: proc(host: ptr ClapHost, extensionId: cstring): pointer {.cdecl.}
    requestRestart*: proc(host: ptr ClapHost) {.cdecl.}
    requestProcess*: proc(host: ptr ClapHost) {.cdecl.}
    requestCallback*: proc(host: ptr ClapHost) {.cdecl.}

  ClapPlugin* {.bycopy.} = object
    desc*: ptr ClapPluginDescriptor
    pluginData*: pointer
    init*: proc(plugin: ptr ClapPlugin): bool {.cdecl.}
    destroy*: proc(plugin: ptr ClapPlugin) {.cdecl.}
    activate*: proc(
      plugin: ptr ClapPlugin,
      sampleRate: cdouble,
      minFramesCount: uint32,
      maxFramesCount: uint32,
    ): bool {.cdecl.}
    deactivate*: proc(plugin: ptr ClapPlugin) {.cdecl.}
    startProcessing*: proc(plugin: ptr ClapPlugin): bool {.cdecl.}
    stopProcessing*: proc(plugin: ptr ClapPlugin) {.cdecl.}
    reset*: proc(plugin: ptr ClapPlugin) {.cdecl.}
    process*: proc(plugin: ptr ClapPlugin, process: ptr ClapProcess): int32 {.cdecl.}
    getExtension*: proc(plugin: ptr ClapPlugin, id: cstring): pointer {.cdecl.}
    onMainThread*: proc(plugin: ptr ClapPlugin) {.cdecl.}

  ClapPluginFactory* {.bycopy.} = object
    getPluginCount*: proc(factory: ptr ClapPluginFactory): uint32 {.cdecl.}
    getPluginDescriptor*: proc(
      factory: ptr ClapPluginFactory, index: uint32
    ): ptr ClapPluginDescriptor {.cdecl.}
    createPlugin*: proc(
      factory: ptr ClapPluginFactory, host: ptr ClapHost, pluginId: cstring
    ): ptr ClapPlugin {.cdecl.}

  ClapAudioPortInfo* {.bycopy.} = object
    id*: ClapId
    name*: array[ClapNameSize, char]
    flags*: uint32
    channelCount*: uint32
    portType*: cstring
    inPlacePair*: ClapId

  ClapPluginAudioPorts* {.bycopy.} = object
    count*: proc(plugin: ptr ClapPlugin, isInput: bool): uint32 {.cdecl.}
    get*: proc(
      plugin: ptr ClapPlugin, index: uint32, isInput: bool, info: ptr ClapAudioPortInfo
    ): bool {.cdecl.}

  ClapParamInfo* {.bycopy.} = object
    id*: ClapId
    flags*: uint32
    cookie*: pointer
    name*: array[ClapNameSize, char]
    module*: array[ClapPathSize, char]
    minValue*: cdouble
    maxValue*: cdouble
    defaultValue*: cdouble

  ClapPluginParams* {.bycopy.} = object
    count*: proc(plugin: ptr ClapPlugin): uint32 {.cdecl.}
    getInfo*: proc(
      plugin: ptr ClapPlugin, paramIndex: uint32, paramInfo: ptr ClapParamInfo
    ): bool {.cdecl.}
    getValue*: proc(
      plugin: ptr ClapPlugin, paramId: ClapId, outValue: ptr cdouble
    ): bool {.cdecl.}
    valueToText*: proc(
      plugin: ptr ClapPlugin,
      paramId: ClapId,
      value: cdouble,
      outBuffer: cstring,
      outBufferCapacity: uint32,
    ): bool {.cdecl.}
    textToValue*: proc(
      plugin: ptr ClapPlugin,
      paramId: ClapId,
      paramValueText: cstring,
      outValue: ptr cdouble,
    ): bool {.cdecl.}
    flush*: proc(
      plugin: ptr ClapPlugin,
      inEvents: ptr ClapInputEvents,
      outEvents: ptr ClapOutputEvents,
    ) {.cdecl.}

  ClapPluginState* {.bycopy.} = object
    save*: proc(plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.}
    load*: proc(plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.}

  ClapAudioBuffer* {.bycopy.} = object
    data32*: ptr ptr cfloat
    data64*: ptr ptr cdouble
    channelCount*: uint32
    latency*: uint32
    constantMask*: uint64

  ClapEventHeader* {.bycopy.} = object
    size*: uint32
    time*: uint32
    spaceId*: uint16
    eventType*: uint16
    flags*: uint32

  ClapEventParamValue* {.bycopy.} = object
    header*: ClapEventHeader
    paramId*: ClapId
    cookie*: pointer
    noteId*: int32
    portIndex*: int16
    channel*: int16
    key*: int16
    value*: cdouble

  ClapInputEvents* {.bycopy.} = object
    ctx*: pointer
    size*: proc(list: ptr ClapInputEvents): uint32 {.cdecl.}
    get*: proc(list: ptr ClapInputEvents, index: uint32): ptr ClapEventHeader {.cdecl.}

  ClapOutputEvents* {.bycopy.} = object
    ctx*: pointer
    tryPush*:
      proc(list: ptr ClapOutputEvents, event: ptr ClapEventHeader): bool {.cdecl.}

  ClapProcess* {.bycopy.} = object
    steadyTime*: int64
    framesCount*: uint32
    transport*: pointer
    audioInputs*: ptr ClapAudioBuffer
    audioOutputs*: ptr ClapAudioBuffer
    audioInputsCount*: uint32
    audioOutputsCount*: uint32
    inEvents*: ptr ClapInputEvents
    outEvents*: ptr ClapOutputEvents

  ClapOStream* {.bycopy.} = object
    ctx*: pointer
    write*:
      proc(stream: ptr ClapOStream, buffer: pointer, size: uint64): int64 {.cdecl.}

  ClapIStream* {.bycopy.} = object
    ctx*: pointer
    read*: proc(stream: ptr ClapIStream, buffer: pointer, size: uint64): int64 {.cdecl.}

static:
  doAssert sizeof(ClapVersion) == 12

proc clapVersion*(): ClapVersion =
  ClapVersion(
    major: ClapVersionMajor, minor: ClapVersionMinor, revision: ClapVersionRevision
  )

proc versionCompatible*(version: ClapVersion): bool =
  version.major >= 1
