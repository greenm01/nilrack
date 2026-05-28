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

  # Opaque handles for wgpu objects. The adapter casts these to the real
  # wgpu pointer types internally. Nothing outside src/render/ sees wgpu types.
  WgpuInstance* = distinct pointer
  WgpuSurface* = distinct pointer
  WgpuAdapter* = distinct pointer
  WgpuDevice* = distinct pointer
  WgpuQueue* = distinct pointer

  WgpuBackend* = object
    instance*: WgpuInstance
    surface*: WgpuSurface
    adapter*: WgpuAdapter
    device*: WgpuDevice
    queue*: WgpuQueue
    width*: uint32
    height*: uint32
    surfaceFormat*: uint32
    surfaceAlphaMode*: uint32

  Renderer* = object
    backend*: WgpuBackend
