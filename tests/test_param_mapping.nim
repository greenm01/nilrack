import std/[options, unittest]

import ../src/state/engine
import ../src/systems/param_mapping

suite "param mapping":
  test "maps parameter values to normalized slider values":
    let param = ParamData(minVal: -12.0, maxVal: 12.0, currentVal: 0.0)

    check param.normalizedParamValue() == 0.5'f32
    check param.paramValueFromNormalized(0.0) == -12.0
    check param.paramValueFromNormalized(1.0) == 12.0
    check param.paramValueFromNormalized(2.0) == 12.0

  test "maps slider hit x to parameter value":
    let param = ParamData(minVal: 0.0, maxVal: 100.0, currentVal: 0.0)
    let rect = Rect(x: 10.0'f32, y: 20.0'f32, w: 200.0'f32, h: 8.0'f32)

    check param.paramValueAtX(rect, 10.0'f32) == 0.0
    check param.paramValueAtX(rect, 110.0'f32) == 50.0
    check param.paramValueAtX(rect, 210.0'f32) == 100.0

  test "finds visible parameter slider under pointer":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    let nodeId = model.nodeCreate(rackId, nkPlugin, "plugin")
    model.nodeMove(nodeId, 40.0'f32, 50.0'f32)
    model.nodes.mEntity(nodeId).w = 340.0'f32
    let hidden = model.paramCreate(nodeId, "Hidden", 0.0, 1.0, 0.5)
    let visible = model.paramCreate(nodeId, "Visible", 0.0, 1.0, 0.5)
    model.params.mEntity(hidden).hidden = true

    let rect = model.nodes.mEntity(nodeId).paramSliderRect(0)
    let hit = model.paramSliderAt(rect.x + 1.0'f32, rect.y + 1.0'f32)

    check hit == some(visible)
