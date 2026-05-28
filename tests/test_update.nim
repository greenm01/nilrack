import std/[options, unittest]

import ../src/state/engine
import ../src/systems/effect_queue
import ../src/systems/update
import ../src/systems/param_mapping
import ../src/systems/ui_geometry

suite "update dispatch":
  test "resize message emits a resize command":
    var model = NilrackModel()
    var actions: ActionLog
    var effects: EffectQueue
    var commands: UpdateCommandQueue

    model.dispatchMsg(
      actions, effects, commands, Msg(kind: msgResize, resizeW: 800, resizeH: 600)
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

    model.dispatchMsg(actions, effects, commands, Msg(kind: msgKeyPress, keyCode: 1))

    var command: UpdateCommand
    check commands.popUpdateCommand(command)
    check command.kind == uckClose

  test "parameter click mutates model and emits audio command":
    var model = NilrackModel()
    var actions: ActionLog
    var effects: EffectQueue
    var commands: UpdateCommandQueue
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

    model.dispatchMsg(
      actions,
      effects,
      commands,
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
    let rackId = model.rackCreate("rack")
    let nodeId = model.nodeCreate(rackId, nkPlugin, "plugin")
    model.nodeMove(nodeId, 40.0'f32, 50.0'f32)
    model.nodeResize(nodeId, 340.0'f32, 180.0'f32)
    let rect = model.nodeData(nodeId).get.pluginBypassToggleRect()

    model.dispatchMsg(
      actions,
      effects,
      commands,
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
