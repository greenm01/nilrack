import std/[math, os, unicode]

import pixie

import ../types/render_values

const
  AtlasWidth* = 512
  AtlasHeight* = 512
  AtlasFontSize* = 14.0'f32
  AtlasPadding = 2
  FirstPrintable = 32
  LastPrintable = 126
  FallbackChar = '?'

proc glyphRunes*(text: string): seq[uint32] =
  var i = 0
  while i < text.len:
    let b = text[i].uint8
    if b in uint8(FirstPrintable) .. uint8(LastPrintable):
      result.add(uint32(b))
      inc i
    elif b < 0x80'u8:
      result.add(uint32(FallbackChar))
      inc i
    else:
      result.add(uint32(FallbackChar))
      let extra =
        if (b and 0xE0'u8) == 0xC0'u8:
          1
        elif (b and 0xF0'u8) == 0xE0'u8:
          2
        elif (b and 0xF8'u8) == 0xF0'u8:
          3
        else:
          0
      inc i
      var skipped = 0
      while skipped < extra and i < text.len and (text[i].uint8 and 0xC0'u8) == 0x80'u8:
        inc i
        inc skipped

proc glyphFor*(atlas: TextAtlas, rune: uint32): GlyphInfo =
  if rune < atlas.glyphs.len.uint32 and atlas.glyphs[rune].advance > 0:
    atlas.glyphs[rune]
  else:
    atlas.fallback

proc fontPath*(): string =
  currentSourcePath().parentDir().parentDir().parentDir() /
    "third_party/fonts/0xproto/0xProto-Regular.ttf"

proc buildTextAtlas*(path = fontPath()): TextAtlas =
  let typeface = readTypeface(path)
  let font = newFont(typeface)
  font.size = AtlasFontSize
  font.paint.color = color(1, 1, 1, 1)

  let image = newImage(AtlasWidth, AtlasHeight)
  let lineHeight = ceil(font.defaultLineHeight).int
  var penX = AtlasPadding
  var penY = AtlasPadding

  result.width = AtlasWidth.uint32
  result.height = AtlasHeight.uint32
  result.fontSize = AtlasFontSize
  result.lineHeight = lineHeight.float32

  for code in FirstPrintable .. LastPrintable:
    let text = $Rune(code)
    let arrangement = font.typeset(text, wrap = false)
    if arrangement.selectionRects.len == 0:
      continue

    let selection = arrangement.selectionRects[0]
    let glyphW = max(1, ceil(selection.w).int)
    let glyphH = max(1, lineHeight)
    if penX + glyphW + AtlasPadding > AtlasWidth:
      penX = AtlasPadding
      penY += glyphH + AtlasPadding
    if penY + glyphH + AtlasPadding > AtlasHeight:
      raise newException(PixieError, "text atlas is too small")

    image.fillText(
      arrangement,
      translate(vec2(penX.float32 - selection.x, penY.float32 - selection.y)),
    )

    let info = GlyphInfo(
      rune: code.uint32,
      x: penX.float32,
      y: penY.float32,
      w: glyphW.float32,
      h: glyphH.float32,
      u0: penX.float32 / AtlasWidth.float32,
      v0: penY.float32 / AtlasHeight.float32,
      u1: (penX + glyphW).float32 / AtlasWidth.float32,
      v1: (penY + glyphH).float32 / AtlasHeight.float32,
      advance: selection.w,
    )
    result.glyphs[code] = info
    if code == int(FallbackChar):
      result.fallback = info

    penX += glyphW + AtlasPadding

  if result.fallback.advance <= 0:
    raise newException(PixieError, "fallback glyph was not built")

  result.pixels.setLen(AtlasWidth * AtlasHeight * 4)
  for i, px in image.data:
    let outIdx = i * 4
    result.pixels[outIdx + 0] = px.r
    result.pixels[outIdx + 1] = px.g
    result.pixels[outIdx + 2] = px.b
    result.pixels[outIdx + 3] = px.a
