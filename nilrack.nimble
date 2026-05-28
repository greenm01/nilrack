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

task buildVst3UiShim, "Build the optional nilamp VST3 Wayland UI shim":
  exec "mkdir -p build"
  exec "g++ -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror -fPIC -shared " &
    "-I/home/niltempus/dev/wayembed/include " &
    "-I/home/niltempus/dev/nilamp/third_party/vst3sdk " & "src/plugins/vst3_ui_shim.cpp " &
    "/home/niltempus/dev/wayembed/zig-out/lib/libwayembed.a " &
    "-lwayland-client -lwayland-server -ldl -lm " & "-o build/libnilrack_vst3_ui_shim.so"

task tidy, "Remove local build artifacts":
  for path in ["src/nilrack"]:
    if fileExists(path):
      rmFile(path)
  for path in [".nimcache", "nimcache", "src/.nimcache", "src/nimcache"]:
    if dirExists(path):
      rmDir(path)
