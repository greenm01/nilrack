import std/[options, unittest]

import ../src/state/engine
import ../src/systems/effect_queue
import ../src/systems/render_projection
import ../src/systems/update
import ../src/systems/param_mapping
import ../src/systems/ui_geometry

suite "update dispatch":
  test "resize message emits a resize command":
    var model = NilrackModel()
    var actions: ActionLog
    var effects: EffectQueue
    var commands: UpdateCommandQueue
    let targets = InputTargetList()

    model.dispatchMsg(
      actions,
      effects,
      commands,
      targets,
      Msg(kind: msgResize, resizeW: 800, resizeH: 600),
    )

    var command: UpdateCommand
    check commands.popUpdateCommand(command)
    check command.kind == uckResize
    check command.width == 800
    check command.height == 600

  test "escape key emits close command":
    var model = NilrackModel()
    var actions: ActionLog
    var effects: EffectQueue
    var commands: UpdateCommandQueue
    let targets = InputTargetList()

    model.dispatchMsg(
      actions, effects, commands, targets, Msg(kind: msgKeyPress, keyCode: 1)
    )

    var command: UpdateCommand
    check commands.popUpdateCommand(command)
    check command.kind == uckClose

  test "parameter click mutates model and emits audio command":
    var model = NilrackModel()
    var actions: ActionLog
    var effects: EffectQueue
    var commands: UpdateCommandQueue
    var frame: NilDrawList
    var targets: InputTargetList
    let rackId = model.rackCreate("rack")
    let nodeId = model.nodeCreate(rackId, nkPlugin, "plugin")
    model.nodeMove(nodeId, 40.0'f32, 50.0'f32)
    model.nodeResize(nodeId, 340.0'f32, 180.0'f32)
    let pluginId = model.pluginAttachToNode(
      nodeId, paClap, "/tmp/example.clap", "dev.nilrack.example", "Example"
    )
    let paramId = model.paramCreate(nodeId, "Gain", 0.0, 1.0, 0.5)
    let node = model.nodeData(nodeId).get
    let rect = node.paramSliderRect(0)
    frame.project(targets, model, 800.0'f32, 600.0'f32, 0.0'f32, 0.0'f32)

    model.dispatchMsg(
      actions,
      effects,
      commands,
      targets,
      Msg(
        kind: msgPointerButton,
        btnButton: 1,
        btnPressed: true,
        btnX: rect.x + rect.w * 0.25'f32,
        btnY: rect.y + 1.0'f32,
      ),
    )

    let param = model.paramData(paramId).get
    check param.currentVal == 0.25
    var command: UpdateCommand
    check commands.popUpdateCommand(command)
    check command.kind == uckEnqueueParamValue
    check command.pluginId == pluginId
    check command.paramId == paramId
    check command.normalizedValue == 0.25

  test "bypass click mutates model and requests plan publish":
    var model = NilrackModel()
    var actions: ActionLog
    var effects: EffectQueue
    var commands: UpdateCommandQueue
    var frame: NilDrawList
    var targets: InputTargetList
    let rackId = model.rackCreate("rack")
    let nodeId = model.nodeCreate(rackId, nkPlugin, "plugin")
    model.nodeMove(nodeId, 40.0'f32, 50.0'f32)
    model.nodeResize(nodeId, 340.0'f32, 180.0'f32)
    let rect = model.nodeData(nodeId).get.pluginBypassToggleRect()
    frame.project(targets, model, 800.0'f32, 600.0'f32, 0.0'f32, 0.0'f32)

    model.dispatchMsg(
      actions,
      effects,
      commands,
      targets,
      Msg(
        kind: msgPointerButton,
        btnButton: 1,
        btnPressed: true,
        btnX: rect.x + 1.0'f32,
        btnY: rect.y + 1.0'f32,
      ),
    )

    check model.nodeData(nodeId).get.bypassed
    var command: UpdateCommand
    check commands.popUpdateCommand(command)
    check command.kind == uckPublishProcessPlan
    var effect: Effect
    check effects.popEffect(effect)
    check effect.kind == ekProcessPlanDirty

  test "plugin browser format click changes filter":
    var model = NilrackModel()
    model.pluginBrowser = PluginBrowserState(enabled: true, cachePresent: true)
    var actions: ActionLog
    var effects: EffectQueue
    var commands: UpdateCommandQueue
    var frame: NilDrawList
    var targets: InputTargetList
    frame.project(targets, model, 800.0'f32, 600.0'f32, 0.0'f32, 0.0'f32)

    var clapTarget: InputTargetEntry
    var found = false
    for target in targets.entries:
      if target.kind == itkPluginBrowserFormat and target.browserFormatFilter == pbfClap:
        clapTarget = target
        found = true
    check found

    model.dispatchMsg(
      actions,
      effects,
      commands,
      targets,
      Msg(
        kind: msgPointerButton,
        btnButton: 1,
        btnPressed: true,
        btnX: clapTarget.x + 1.0'f32,
        btnY: clapTarget.y + 1.0'f32,
      ),
    )

    check model.pluginBrowser.formatFilter == pbfClap

  test "plugin browser scroll clamps visible entries":
    var model = NilrackModel()
    model.pluginBrowser = PluginBrowserState(
      enabled: true,
      cachePresent: true,
      entries:
        @[
          PluginBrowserEntry(api: paClap, name: "A"),
          PluginBrowserEntry(api: paClap, name: "B"),
          PluginBrowserEntry(api: paClap, name: "C"),
          PluginBrowserEntry(api: paClap, name: "D"),
          PluginBrowserEntry(api: paClap, name: "E"),
        ],
    )
    var actions: ActionLog
    var effects: EffectQueue
    var commands: UpdateCommandQueue
    var frame: NilDrawList
    var targets: InputTargetList
    frame.project(targets, model, 800.0'f32, 160.0'f32, 0.0'f32, 0.0'f32)

    for i in 0 ..< 10:
      model.dispatchMsg(
        actions,
        effects,
        commands,
        targets,
        Msg(
          kind: msgPointerScroll,
          scrollAxis: 0,
          scrollValue: 1.0'f32,
          scrollX: 20.0'f32,
          scrollY: 100.0'f32,
        ),
      )

    check model.pluginBrowser.scrollOffset == 3

    model.dispatchMsg(
      actions,
      effects,
      commands,
      targets,
      Msg(
        kind: msgPointerScroll,
        scrollAxis: 0,
        scrollValue: -1.0'f32,
        scrollX: 20.0'f32,
        scrollY: 100.0'f32,
      ),
    )

    check model.pluginBrowser.scrollOffset == 2
