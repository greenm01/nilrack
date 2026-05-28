import std/options
import ../types/[core, ui_values]
import ../state/engine

proc hitTest*(model: NilrackModel, x, y: float32): Option[InputTargetId] =
  model.inputTargetAt(x, y)
