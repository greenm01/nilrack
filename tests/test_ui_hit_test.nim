import std/[options, unittest]

import ../src/state/engine
import ../src/systems/render_projection
import ../src/systems/ui_geometry
import ../src/systems/ui_hit_test

suite "ui hit test":
  test "plugin bypass toggle hit maps to node":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    let nodeId = model.nodeCreate(rackId, nkPlugin, "plugin")
    model.nodeMove(nodeId, 40.0'f32, 50.0'f32)
    model.nodes.mEntity(nodeId).w = 300.0'f32
    var frame: NilDrawList
    var targets: InputTargetList
    frame.project(targets, model, 800.0'f32, 600.0'f32, 0.0'f32, 0.0'f32)

    let rect = model.nodes.mEntity(nodeId).pluginBypassToggleRect()
    let hit = targets.bypassToggleAt(rect.x + 1.0'f32, rect.y + 1.0'f32)
    let miss = targets.bypassToggleAt(rect.x - 1.0'f32, rect.y)

    check hit == some(nodeId)
    check miss.isNone

  test "node bypass operation toggles model truth":
    var model = NilrackModel()
    let rackId = model.rackCreate("rack")
    let nodeId = model.nodeCreate(rackId, nkPlugin, "plugin")

    check not model.nodes.mEntity(nodeId).bypassed
    model.nodeToggleBypass(nodeId)
    check model.nodes.mEntity(nodeId).bypassed
    model.nodeSetBypassed(nodeId, false)
    check not model.nodes.mEntity(nodeId).bypassed
