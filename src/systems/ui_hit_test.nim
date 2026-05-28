import std/options
import ../types/core
import ../state/engine

const
  PluginBypassToggleW* = 30.0'f32
  PluginBypassToggleH* = 16.0'f32
  PluginBypassToggleRightPad* = 12.0'f32
  PluginBypassToggleTopPad* = 7.0'f32

proc hitTest*(model: NilrackModel, x, y: float32): Option[InputTargetId] =
  model.inputTargetAt(x, y)

proc pluginBypassToggleRect*(node: NodeData): Rect =
  let w = if node.w > 0.0'f32: node.w else: 320.0'f32
  Rect(
    x: node.x + w - PluginBypassToggleRightPad - PluginBypassToggleW,
    y: node.y + PluginBypassToggleTopPad,
    w: PluginBypassToggleW,
    h: PluginBypassToggleH,
  )

proc contains(rect: Rect, x, y: float32): bool =
  x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h

proc bypassToggleAt*(model: NilrackModel, x, y: float32): Option[NodeId] =
  for node in model.nodes.data:
    if node.kind != nkPlugin:
      continue
    if node.pluginBypassToggleRect().contains(x, y):
      return some(node.id)
  none(NodeId)
