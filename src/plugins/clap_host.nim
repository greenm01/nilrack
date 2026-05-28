import std/[dynlib, os, strformat, strutils]

import ../types/[core, model, plugin_values]
import clap_api

type
  ClapHostRuntime = object
    requestRestartCount: uint32
    requestProcessCount: uint32
    requestCallbackCount: uint32

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
    entryInitialized: bool
    pluginInitialized: bool

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

proc hostGetExtension(host: ptr ClapHost, extensionId: cstring): pointer {.cdecl.} =
  discard host
  discard extensionId
  nil

proc hostRequestRestart(host: ptr ClapHost) {.cdecl.} =
  if not host.isNil and not host.hostData.isNil:
    let runtime = cast[ptr ClapHostRuntime](host.hostData)
    inc runtime.requestRestartCount

proc hostRequestProcess(host: ptr ClapHost) {.cdecl.} =
  if not host.isNil and not host.hostData.isNil:
    let runtime = cast[ptr ClapHostRuntime](host.hostData)
    inc runtime.requestProcessCount

proc hostRequestCallback(host: ptr ClapHost) {.cdecl.} =
  if not host.isNil and not host.hostData.isNil:
    let runtime = cast[ptr ClapHostRuntime](host.hostData)
    inc runtime.requestCallbackCount

proc newHostBox(): ClapHostBox =
  result = ClapHostBox()
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

proc close*(loaded: ClapLoadedPlugin) =
  if loaded.isNil:
    return
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

    var descriptor = descriptorFromClap(pluginPath, desc)
    queryAudioPorts(loaded.plugin, descriptor)
    queryParams(loaded.plugin, descriptor)
    queryState(loaded.plugin, descriptor)

    ClapLoadResult(ok: true, plugin: loaded, descriptor: descriptor)
  except CatchableError as e:
    loaded.close()
    fail("CLAP load failed: " & e.msg)
