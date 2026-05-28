import std/unittest

import kdl

import ../src/systems/plugin_scan
import ../src/types/[model, plugin_values]

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
