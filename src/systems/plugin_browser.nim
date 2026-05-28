import std/[options, os, strutils]

import kdl

import ../types/model
import plugin_scan

const
  PluginBrowserPanelWidth* = 300.0'f32
  PluginBrowserHeaderHeight* = 68.0'f32
  PluginBrowserRowHeight* = 46.0'f32

proc pluginApiLabel*(api: PluginApi): string =
  case api
  of paClap: "CLAP"
  of paLv2: "LV2"
  of paVst3: "VST3"

proc pluginApiFilter*(api: PluginApi): PluginBrowserFormatFilter =
  case api
  of paClap: pbfClap
  of paLv2: pbfLv2
  of paVst3: pbfVst3

proc pluginBrowserFormatLabel*(filter: PluginBrowserFormatFilter): string =
  case filter
  of pbfAll: "All"
  of pbfClap: "CLAP"
  of pbfLv2: "LV2"
  of pbfVst3: "VST3"

proc parsePluginApi(name: string): Option[PluginApi] =
  case name
  of "clap":
    some(paClap)
  of "lv2":
    some(paLv2)
  of "vst3":
    some(paVst3)
  else:
    none(PluginApi)

proc childNamed(node: KdlNode, name: string): Option[KdlNode] =
  for child in node.children:
    if child.name == name:
      return some(child)
  none(KdlNode)

proc countAudioPorts(node: KdlNode, direction: string): uint32 =
  for child in node.children:
    if child.name != "port":
      continue
    try:
      if child.props["kind"].get(string) == "audio" and
          child.props["direction"].get(string) == direction:
        inc result
    except CatchableError:
      discard

proc countParams(node: KdlNode): uint32 =
  for child in node.children:
    if child.name == "param":
      inc result

proc entryFromScanNode(node: KdlNode): Option[PluginBrowserEntry] =
  try:
    if node.name != "plugin-scan":
      return none(PluginBrowserEntry)
    if node.props["schema"].get(uint32) != PluginScanSchemaVersion.uint32:
      return none(PluginBrowserEntry)
    if node.props["status"].get(string) != "ok":
      return none(PluginBrowserEntry)
    let api = parsePluginApi(node.props["format"].get(string))
    if api.isNone:
      return none(PluginBrowserEntry)
    let descriptor = node.childNamed("descriptor")
    if descriptor.isNone:
      return none(PluginBrowserEntry)
    let props = descriptor.get.props
    some(
      PluginBrowserEntry(
        api: api.get,
        path: node.props["path"].get(string),
        name: props["name"].get(string),
        vendor: props["vendor"].get(string),
        version: props["version"].get(string),
        audioInputCount: node.countAudioPorts("in"),
        audioOutputCount: node.countAudioPorts("out"),
        paramCount: node.countParams(),
      )
    )
  except CatchableError:
    none(PluginBrowserEntry)

proc loadPluginBrowserEntries*(cachePath: string): PluginBrowserState =
  result.enabled = cachePath.len > 0
  result.cachePath = cachePath
  result.cachePresent = cachePath.len > 0 and fileExists(cachePath)
  if not result.cachePresent:
    return

  let cache = loadScanCache(cachePath)
  for node in cache:
    let entry = entryFromScanNode(node)
    if entry.isSome:
      result.entries.add(entry.get)

proc pluginBrowserMatches*(state: PluginBrowserState, entry: PluginBrowserEntry): bool =
  if state.formatFilter != pbfAll and state.formatFilter != entry.api.pluginApiFilter():
    return false
  if state.nameFilter.strip().len == 0:
    return true
  entry.name.toLowerAscii().contains(state.nameFilter.strip().toLowerAscii())

proc filteredPluginBrowserEntries*(state: PluginBrowserState): seq[PluginBrowserEntry] =
  for entry in state.entries:
    if state.pluginBrowserMatches(entry):
      result.add(entry)

proc maxPluginBrowserScroll*(state: PluginBrowserState, panelHeight: float32): int =
  let visibleRows =
    max(0, int((panelHeight - PluginBrowserHeaderHeight) / PluginBrowserRowHeight))
  max(0, state.filteredPluginBrowserEntries().len - visibleRows)

proc clampPluginBrowserScroll*(state: var PluginBrowserState, panelHeight: float32) =
  state.scrollOffset =
    min(max(state.scrollOffset, 0), state.maxPluginBrowserScroll(panelHeight))

proc setPluginBrowserFormat*(
    state: var PluginBrowserState, filter: PluginBrowserFormatFilter
) =
  state.formatFilter = filter
  state.scrollOffset = 0

proc scrollPluginBrowser*(
    state: var PluginBrowserState, deltaRows: int, panelHeight: float32
) =
  state.scrollOffset += deltaRows
  state.clampPluginBrowserScroll(panelHeight)
