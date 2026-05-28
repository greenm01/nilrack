import ../types/[core, render_values]

proc clear*(list: var NilDrawList) =
  list.cmds.setLen(0)

proc addRect*(list: var NilDrawList, x, y, w, h: float32, color: Color) =
  list.cmds.add(NilDrawCmd(kind: dcRect, x: x, y: y, w: w, h: h, color: color))

proc addRoundedRect*(list: var NilDrawList, x, y, w, h, radius: float32, color: Color) =
  list.cmds.add(
    NilDrawCmd(
      kind: dcRoundedRect, x: x, y: y, w: w, h: h, color: color, radius: radius
    )
  )

proc addLine*(
    list: var NilDrawList, x0, y0, x1, y1: float32, color: Color, width: float32 = 1.0
) =
  list.cmds.add(
    NilDrawCmd(
      kind: dcLine, x: x0, y: y0, x1: x1, y1: y1, strokeColor: color, strokeWidth: width
    )
  )

proc addTextRun*(list: var NilDrawList, x, y: float32, text: string, color: Color) =
  list.cmds.add(NilDrawCmd(kind: dcTextRun, x: x, y: y, text: text, color: color))

proc addClipPush*(list: var NilDrawList, x, y, w, h: float32) =
  list.cmds.add(NilDrawCmd(kind: dcClipPush, x: x, y: y, w: w, h: h))

proc addClipPop*(list: var NilDrawList) =
  list.cmds.add(NilDrawCmd(kind: dcClipPop))
