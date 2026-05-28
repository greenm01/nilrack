import std/unittest

import ../src/state/engine
import ../src/systems/render_projection

proc hasText(list: NilDrawList, value: string): bool =
  for cmd in list.cmds:
    if cmd.kind == dcTextRun and cmd.text == value:
      return true
  false

suite "render projection":
  test "draws JACK input and output nodes":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    discard model.ensureRackAudioIoNodes(rackId)
    var frame: NilDrawList
    var targets: InputTargetList

    frame.project(targets, model, 1280.0'f32, 720.0'f32, 0.0'f32, 0.0'f32)

    check frame.hasText("JACK Input")
    check frame.hasText("JACK Output")

  test "draws plugin browser and shifts rack canvas":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    discard model.ensureRackAudioIoNodes(rackId)
    model.pluginBrowser = PluginBrowserState(
      enabled: true,
      cachePresent: true,
      entries: @[PluginBrowserEntry(api: paClap, name: "Example", paramCount: 3)],
    )
    var frame: NilDrawList
    var targets: InputTargetList

    frame.project(targets, model, 1280.0'f32, 720.0'f32, 0.0'f32, 0.0'f32)

    check frame.hasText("Plugins")
    check frame.hasText("Example")
    var foundFormatTarget = false
    for target in targets.entries:
      if target.kind == itkPluginBrowserFormat and target.browserFormatFilter == pbfClap:
        foundFormatTarget = true
    check foundFormatTarget

    var shiftedJackTitle = false
    for cmd in frame.cmds:
      if cmd.kind == dcTextRun and cmd.text == "JACK Input":
        shiftedJackTitle = cmd.x > 300.0'f32
    check shiftedJackTitle

  test "still emits generated parameter targets for plugin nodes":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    let nodeId = model.nodeCreate(rackId, nkPlugin, "plugin")
    model.nodeMove(nodeId, 400.0'f32, 96.0'f32)
    model.nodeResize(nodeId, 340.0'f32, 180.0'f32)
    let paramId = model.paramCreate(nodeId, "Gain", 0.0, 1.0, 0.5)
    var frame: NilDrawList
    var targets: InputTargetList

    frame.project(targets, model, 1280.0'f32, 720.0'f32, 0.0'f32, 0.0'f32)

    var found = false
    for target in targets.entries:
      if target.kind == itkParamSlider and target.paramId == paramId:
        found = true
    check found
