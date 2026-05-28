import std/[os, strutils, unittest]

const declarationPrefixes =
  ["proc ", "func ", "method ", "iterator ", "template ", "macro ", "converter "]

proc lineHasProcType(line: string): bool =
  let stripped = line.strip()
  stripped.startsWith("proc(") or stripped.startsWith("proc[") or line.contains(
    "= proc"
  ) or line.contains(": proc") or line.contains(" proc(")

suite "data code boundary":
  test "types modules contain passive data only":
    var checkedFiles = 0
    for path in walkFiles("src/types/*.nim"):
      inc checkedFiles
      let source = readFile(path)
      let lines = source.splitLines()
      for lineNumber in 0 ..< lines.len:
        let line = lines[lineNumber]
        let stripped = line.strip()
        for prefix in declarationPrefixes:
          checkpoint path & ":" & $(lineNumber + 1) & " must not declare " & prefix
          check not stripped.startsWith(prefix)
        checkpoint path & ":" & $(lineNumber + 1) & " must not contain proc types"
        check not line.lineHasProcType()
    check checkedFiles > 0
