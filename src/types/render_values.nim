import core

type
  NilDrawCmdKind* = enum
    dcRect
    dcRoundedRect
    dcBorder
    dcLine
    dcBezier
    dcTextRun
    dcImage
    dcClipPush
    dcClipPop
    dcMeterBatch

  NilDrawCmd* = object
    kind*: NilDrawCmdKind
    x*, y*, w*, h*: float32
    color*: Color
    radius*: float32
    x1*, y1*, x2*, y2*: float32
    strokeColor*: Color
    strokeWidth*: float32
    text*: string
    textureId*: TextureId

  NilDrawList* = object
    cmds*: seq[NilDrawCmd]
