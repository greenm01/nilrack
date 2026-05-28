import std/options
import ../types/core
import ../types/model
import ../types/ui_values

proc contains(entry: InputTargetEntry, x, y: float32): bool =
  x >= entry.x and x < entry.x + entry.w and y >= entry.y and y < entry.y + entry.h

proc targetAt*(targets: InputTargetList, x, y: float32): Option[InputTargetEntry] =
  if targets.entries.len == 0:
    return none(InputTargetEntry)
  for i in countdown(targets.entries.high, 0):
    if targets.entries[i].contains(x, y):
      return some(targets.entries[i])
  none(InputTargetEntry)

proc bypassToggleAt*(targets: InputTargetList, x, y: float32): Option[NodeId] =
  let target = targets.targetAt(x, y)
  if target.isSome and target.get.kind == itkNodeBypass:
    return some(target.get.nodeId)
  none(NodeId)

proc paramSliderAt*(targets: InputTargetList, x, y: float32): Option[ParamId] =
  let target = targets.targetAt(x, y)
  if target.isSome and target.get.kind == itkParamSlider:
    return some(target.get.paramId)
  none(ParamId)
