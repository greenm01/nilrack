import ../types/[core, render_values]
import ../render/draw_list

proc layoutShell*(
    list: var NilDrawList,
    width, height: float32,
    meterIn: float32,
    meterOut: float32,
    contentOffsetX: float32 = 0.0'f32,
) =
  let stripH = height * 0.08
  let canvasH = height - stripH

  list.addRect(0, 0, width, canvasH, Color(r: 0.10, g: 0.10, b: 0.10, a: 1.0))
  list.addRect(0, canvasH, width, stripH, Color(r: 0.14, g: 0.14, b: 0.14, a: 1.0))
  list.addTextRun(
    contentOffsetX + 12.0'f32,
    12.0'f32,
    "nilrack",
    Color(r: 0.82, g: 0.86, b: 0.90, a: 1.0),
  )

  let meterW = 6.0'f32
  let meterPad = 4.0'f32
  let meterX1 = width - meterPad - meterW
  let meterX2 = meterX1 - meterPad - meterW
  let meterMaxH = stripH - 4.0'f32
  let meterY = canvasH + 2.0'f32
  let green = Color(r: 0.2, g: 0.7, b: 0.3, a: 1.0)
  let textColor = Color(r: 0.70, g: 0.75, b: 0.78, a: 1.0)

  list.addTextRun(meterX2 - 28.0'f32, canvasH + 8.0'f32, "IN", textColor)
  list.addTextRun(meterX1 - 34.0'f32, canvasH + 8.0'f32, "OUT", textColor)

  if meterIn > 0.001'f32:
    let h = meterMaxH * meterIn
    list.addRect(meterX2, meterY + meterMaxH - h, meterW, h, green)

  if meterOut > 0.001'f32:
    let h = meterMaxH * meterOut
    list.addRect(meterX1, meterY + meterMaxH - h, meterW, h, green)
