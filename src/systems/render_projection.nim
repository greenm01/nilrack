import std/options

import ../types/[core, render_values, ui_values]
import ../state/engine
import ../render/draw_list
import param_mapping
import ui_geometry
import ui_layout

proc shortText(value: string, maxChars: int): string =
  if value.len <= maxChars:
    value
  elif maxChars <= 3:
    value[0 ..< maxChars]
  else:
    value[0 ..< maxChars - 3] & "..."

proc clearTargets(targets: var InputTargetList) =
  targets.entries.setLen(0)

proc addTarget(
    targets: var InputTargetList,
    kind: InputTargetKind,
    nodeId: NodeId,
    paramId: ParamId,
    rect: Rect,
) =
  targets.entries.add(
    InputTargetEntry(
      id: InputTargetId(targets.entries.len.uint32 + 1'u32),
      kind: kind,
      nodeId: nodeId,
      paramId: paramId,
      x: rect.x,
      y: rect.y,
      w: rect.w,
      h: rect.h,
    )
  )

proc layoutHostIoNodes(list: var NilDrawList, model: NilrackModel) =
  let inputPanel = Color(r: 0.16, g: 0.32, b: 0.26, a: 1.0)
  let outputPanel = Color(r: 0.36, g: 0.21, b: 0.24, a: 1.0)
  let hostBorder = Color(r: 0.62, g: 0.72, b: 0.68, a: 1.0)
  let header = Color(r: 0.28, g: 0.31, b: 0.33, a: 1.0)
  let text = Color(r: 0.88, g: 0.91, b: 0.90, a: 1.0)
  let mutedText = Color(r: 0.78, g: 0.84, b: 0.82, a: 1.0)
  let portColor = Color(r: 0.78, g: 0.90, b: 0.58, a: 1.0)

  for node in model.nodes.data:
    if node.kind == nkPlugin:
      continue
    let x = node.x
    let y = node.y
    let w = if node.w > 0.0'f32: node.w else: 240.0'f32
    let h = if node.h > 0.0'f32: node.h else: 96.0'f32
    let panel = if node.kind == nkInput: inputPanel else: outputPanel

    list.addRect(x, y, w, h, hostBorder)
    list.addRect(x + 2.0'f32, y + 2.0'f32, w - 4.0'f32, h - 4.0'f32, panel)
    list.addRect(x + 2.0'f32, y + 2.0'f32, w - 4.0'f32, 28.0'f32, header)
    list.addTextRun(x + 12.0'f32, y + 8.0'f32, shortText(node.name, 22), text)

    for portId in model.portIdsForNode(node.id):
      let port = model.portData(portId)
      if port.isNone or port.get.kind != pkAudio:
        continue
      let p = port.get
      let px =
        if p.direction == pdOut:
          x + w - 18.0'f32
        else:
          x + 10.0'f32
      let py = y + 52.0'f32
      list.addRect(px, py, 10.0'f32, 10.0'f32, portColor)
      let channels =
        if p.channelCount > 0:
          $p.channelCount & "ch "
        else:
          ""
      if p.direction == pdOut:
        list.addTextRun(
          x + 26.0'f32, py - 3.0'f32, channels & shortText(p.name, 14), mutedText
        )
      else:
        list.addTextRun(
          px + 18.0'f32, py - 3.0'f32, channels & shortText(p.name, 14), mutedText
        )

proc layoutPluginNodes(
    list: var NilDrawList, targets: var InputTargetList, model: NilrackModel
) =
  let panel = Color(r: 0.16, g: 0.17, b: 0.18, a: 1.0)
  let header = Color(r: 0.20, g: 0.22, b: 0.24, a: 1.0)
  let text = Color(r: 0.86, g: 0.89, b: 0.91, a: 1.0)
  let mutedText = Color(r: 0.58, g: 0.63, b: 0.66, a: 1.0)
  let portColor = Color(r: 0.28, g: 0.47, b: 0.62, a: 1.0)
  let sliderBg = Color(r: 0.09, g: 0.10, b: 0.11, a: 1.0)
  let sliderFill = Color(r: 0.42, g: 0.68, b: 0.38, a: 1.0)
  let sliderKnob = Color(r: 0.82, g: 0.86, b: 0.72, a: 1.0)
  let bypassOff = Color(r: 0.25, g: 0.29, b: 0.31, a: 1.0)
  let bypassOn = Color(r: 0.62, g: 0.30, b: 0.26, a: 1.0)

  for node in model.pluginNodes:
    let x = node.x
    let y = node.y
    let w = if node.w > 0.0'f32: node.w else: 320.0'f32
    let h = if node.h > 0.0'f32: node.h else: 180.0'f32

    list.addRect(x, y, w, h, panel)
    list.addRect(x, y, w, 30.0'f32, header)
    list.addTextRun(x + 12.0'f32, y + 8.0'f32, shortText(node.name, 28), text)

    let bypassRect = node.pluginBypassToggleRect()
    targets.addTarget(itkNodeBypass, node.id, NullParamId, bypassRect)
    let bypassColor = if node.bypassed: bypassOn else: bypassOff
    list.addRect(bypassRect.x, bypassRect.y, bypassRect.w, bypassRect.h, bypassColor)
    list.addTextRun(bypassRect.x + 9.0'f32, y + 8.0'f32, "B", text)

    let pluginId = model.pluginForNode(node.id)
    if pluginId.isSome:
      let plugin = model.pluginData(pluginId.get)
      if plugin.isSome and plugin.get.version.len > 0:
        list.addTextRun(
          x + w - 116.0'f32, y + 8.0'f32, shortText(plugin.get.version, 10), mutedText
        )

    for portId in model.portIdsForNode(node.id):
      let port = model.portData(portId)
      if port.isNone:
        continue
      let p = port.get
      let py = y + 42.0'f32 + p.externalIndex.float32 * 18.0'f32
      let px =
        if p.direction == pdIn:
          x + 8.0'f32
        else:
          x + w - 16.0'f32
      list.addRect(px, py, 8.0'f32, 8.0'f32, portColor)
      if p.direction == pdIn:
        list.addTextRun(px + 14.0'f32, py - 3.0'f32, shortText(p.name, 12), mutedText)
      else:
        list.addTextRun(
          x + w - 92.0'f32, py - 3.0'f32, shortText(p.name, 12), mutedText
        )

    var visibleParam = 0
    for paramId in model.paramIdsForNode(node.id):
      let param = model.paramData(paramId)
      if param.isNone or param.get.hidden:
        continue
      let p = param.get
      let rowY = y + 82.0'f32 + visibleParam.float32 * 24.0'f32
      if rowY + 18.0'f32 > y + h - 8.0'f32:
        break
      let label =
        if p.modulePath.len > 0:
          p.modulePath & "/" & p.name
        else:
          p.name
      list.addTextRun(x + 14.0'f32, rowY, shortText(label, 20), text)
      let sx = x + 170.0'f32
      let slider = node.paramSliderRect(visibleParam)
      targets.addTarget(itkParamSlider, node.id, paramId, slider)
      let normalized = p.normalizedParamValue()
      list.addRect(slider.x, slider.y, slider.w, slider.h, sliderBg)
      list.addRect(slider.x, slider.y, slider.w * normalized, slider.h, sliderFill)
      let knobX = slider.x + slider.w * normalized - 2.0'f32
      list.addRect(knobX, slider.y - 2.0'f32, 4.0'f32, slider.h + 4.0'f32, sliderKnob)
      if p.displayText.len > 0:
        list.addTextRun(
          sx, slider.y + slider.h + 2.0'f32, shortText(p.displayText, 16), mutedText
        )
      inc visibleParam

proc project*(
    list: var NilDrawList,
    targets: var InputTargetList,
    model: NilrackModel,
    width, height: float32,
    meterIn, meterOut: float32,
) =
  list.clear()
  targets.clearTargets()
  list.layoutShell(width, height, meterIn, meterOut)
  list.layoutHostIoNodes(model)
  list.layoutPluginNodes(targets, model)
