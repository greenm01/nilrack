import std/[math, options]

import ../state/engine
import ../types/[core, ui_values]

const
  ParamRowStartY* = 82.0'f32
  ParamRowH* = 24.0'f32
  ParamSliderX* = 170.0'f32
  ParamSliderRightPad* = 20.0'f32
  ParamSliderYInset* = 3.0'f32
  ParamSliderH* = 8.0'f32

proc clamp01*(value: float64): float32 =
  if value.isNaN:
    return 0.0'f32
  max(0.0, min(1.0, value)).float32

proc normalizedParamValue*(param: ParamData): float32 =
  let span = param.maxVal - param.minVal
  if span <= 0.0:
    return 0.0'f32
  clamp01((param.currentVal - param.minVal) / span)

proc paramValueFromNormalized*(param: ParamData, normalized: float64): float64 =
  let n = clamp01(normalized).float64
  param.minVal + n * (param.maxVal - param.minVal)

proc paramSliderRect*(node: NodeData, visibleIndex: int): Rect =
  let w = if node.w > 0.0'f32: node.w else: 320.0'f32
  let rowY = node.y + ParamRowStartY + visibleIndex.float32 * ParamRowH
  Rect(
    x: node.x + ParamSliderX,
    y: rowY + ParamSliderYInset,
    w: max(0.0'f32, w - ParamSliderX - ParamSliderRightPad),
    h: ParamSliderH,
  )

proc paramValueAtX*(param: ParamData, rect: Rect, x: float32): float64 =
  if rect.w <= 0.0'f32:
    return param.minVal
  let normalized = ((x - rect.x) / rect.w).float64
  param.paramValueFromNormalized(normalized)

proc contains(rect: Rect, x, y: float32): bool =
  x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h

proc paramSliderAt*(model: NilrackModel, x, y: float32): Option[ParamId] =
  for node in model.nodes.data:
    if node.kind != nkPlugin:
      continue
    var visibleParam = 0
    for paramId in model.paramsForNode(node.id):
      let param = model.params.entity(paramId)
      if param.isNone or param.get.hidden:
        continue
      let rect = node.paramSliderRect(visibleParam)
      if rect.contains(x, y):
        return some(paramId)
      inc visibleParam
  none(ParamId)

proc paramSliderHitAt*(model: NilrackModel, x, y: float32): Option[ParamSliderHit] =
  for node in model.nodes.data:
    if node.kind != nkPlugin:
      continue
    var visibleParam = 0
    for paramId in model.paramsForNode(node.id):
      let param = model.params.entity(paramId)
      if param.isNone or param.get.hidden:
        continue
      let rect = node.paramSliderRect(visibleParam)
      if rect.contains(x, y):
        let normalized =
          if rect.w <= 0.0'f32:
            0.0'f32
          else:
            clamp01(((x - rect.x) / rect.w).float64)
        return some(
          ParamSliderHit(
            paramId: paramId,
            rect: rect,
            normalizedValue: normalized,
            value: param.get.paramValueFromNormalized(normalized.float64),
          )
        )
      inc visibleParam
  none(ParamSliderHit)
