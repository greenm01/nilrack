import std/unittest

import ../src/render/text_atlas

suite "text atlas":
  test "covers printable ASCII":
    let atlas = buildTextAtlas()
    for code in 32 .. 126:
      let glyph = atlas.glyphFor(code.uint32)
      check glyph.advance > 0
      check glyph.u0 >= 0
      check glyph.v0 >= 0
      check glyph.u1 <= 1
      check glyph.v1 <= 1
      check glyph.u0 < glyph.u1
      check glyph.v0 < glyph.v1

  test "uses fallback for unsupported text":
    let runes = glyphRunes("A\226\130\172B")
    check runes == @[uint32('A'), uint32('?'), uint32('B')]

  test "empty text emits no glyphs":
    check glyphRunes("") == newSeq[uint32]()

  test "invalid utf8 emits fallback and does not crash":
    let runes = glyphRunes("A\255B")
    check runes == @[uint32('A'), uint32('?'), uint32('B')]
