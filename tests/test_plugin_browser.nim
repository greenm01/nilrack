import std/[os, unittest]

import ../src/systems/plugin_browser
import ../src/systems/plugin_scan
import ../src/types/[model, plugin_scan_values, plugin_values]

proc browserTestDir(label: string): string =
  result =
    getTempDir() / ("nilrack-plugin-browser-" & $getCurrentProcessId() & "-" & label)
  if dirExists(result):
    removeDir(result)
  createDir(result)

proc descriptor(api: PluginApi, path, name: string): PluginDescriptor =
  PluginDescriptor(
    api: api,
    path: path,
    uri: "dev.nilrack." & name,
    name: name,
    vendor: "niltempus",
    version: "1.0.0",
    ports:
      @[
        PluginPortDescriptor(
          index: 0,
          externalId: 1,
          name: "Audio In",
          kind: pkAudio,
          direction: pdIn,
          channelCount: 2,
          isMain: true,
        ),
        PluginPortDescriptor(
          index: 1,
          externalId: 2,
          name: "Audio Out",
          kind: pkAudio,
          direction: pdOut,
          channelCount: 2,
          isMain: true,
        ),
      ],
    params:
      @[
        PluginParamDescriptor(
          index: 0,
          externalId: 10,
          name: "Gain",
          minVal: 0.0,
          maxVal: 1.0,
          defaultVal: 0.5,
          currentVal: 0.5,
        )
      ],
  )

suite "plugin browser":
  test "loads ok scan cache entries and hides failures":
    let dir = browserTestDir("load")
    defer:
      removeDir(dir)
    let cachePath = dir / "scan-cache.kdl"
    var cache = scanDescriptorToKdlDoc(descriptor(paClap, "/tmp/a.clap", "Alpha"), 1)
    cache.add(
      scanFailedEntryToKdlDoc(
        PluginScanFailedEntry(
          path: "/tmp/broken.clap",
          mtime: 2,
          reason: psfrTimeout,
          exitCode: -1,
          timedOut: true,
          error: "timeout",
        )
      )[0]
    )
    check saveScanCache(cachePath, cache)

    let browser = loadPluginBrowserEntries(cachePath)

    check browser.enabled
    check browser.cachePresent
    check browser.entries.len == 1
    check browser.entries[0].api == paClap
    check browser.entries[0].name == "Alpha"
    check browser.entries[0].audioInputCount == 1
    check browser.entries[0].audioOutputCount == 1
    check browser.entries[0].paramCount == 1

  test "filters by name and format":
    var browser = PluginBrowserState(
      enabled: true,
      cachePresent: true,
      entries:
        @[
          PluginBrowserEntry(api: paClap, name: "Alpha"),
          PluginBrowserEntry(api: paLv2, name: "Beta"),
          PluginBrowserEntry(api: paVst3, name: "Gamma"),
        ],
    )

    browser.nameFilter = "alp"
    check browser.filteredPluginBrowserEntries().len == 1
    check browser.filteredPluginBrowserEntries()[0].name == "Alpha"

    browser.nameFilter = ""
    browser.setPluginBrowserFormat(pbfLv2)
    check browser.filteredPluginBrowserEntries().len == 1
    check browser.filteredPluginBrowserEntries()[0].api == paLv2

  test "tracks missing cache separately from empty cache":
    let browser = loadPluginBrowserEntries("/tmp/nilrack-missing-cache.kdl")

    check browser.enabled
    check not browser.cachePresent
    check browser.entries.len == 0
