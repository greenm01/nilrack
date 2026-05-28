# Package

version = "0.1.0"
author = "Mason Austin Green"
description = "A native Wayland plugin rack for live audio graphs."
license = "MIT"
srcDir = "src"
bin = @["nilrack"]

# Dependencies

requires "nim >= 2.2.0"
requires "nimkdl >= 2.1.0"
requires "https://github.com/panno8M/wayland-nim == 0.1.0"
requires "webgpu >= 25.0.0.0"

task tidy, "Remove local build artifacts":
  for path in ["src/nilrack"]:
    if fileExists(path):
      rmFile(path)
  for path in [".nimcache", "nimcache", "src/.nimcache", "src/nimcache"]:
    if dirExists(path):
      rmDir(path)
