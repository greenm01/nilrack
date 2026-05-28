import std/options
import ../types/core
import ../state/engine
import ui_geometry

proc hitTest*(model: NilrackModel, x, y: float32): Option[InputTargetId] =
  model.inputTargetAt(x, y)

proc contains(rect: Rect, x, y: float32): bool =
  x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h

proc bypassToggleAt*(model: NilrackModel, x, y: float32): Option[NodeId] =
  for node in model.nodes.data:
    if node.kind != nkPlugin:
      continue
    if node.pluginBypassToggleRect().contains(x, y):
      return some(node.id)
  none(NodeId)
