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
  WgpuBuffer* = distinct pointer
  WgpuTexture* = distinct pointer
  WgpuTextureView* = distinct pointer
  WgpuSampler* = distinct pointer
  WgpuBindGroupLayout* = distinct pointer
  WgpuPipelineLayout* = distinct pointer
  WgpuBindGroup* = distinct pointer
  WgpuRenderPipeline* = distinct pointer

  GlyphInfo* = object
    rune*: uint32
    x*, y*, w*, h*: float32
    u0*, v0*, u1*, v1*: float32
    advance*: float32

  TextAtlas* = object
    width*, height*: uint32
    fontSize*: float32
    lineHeight*: float32
    pixels*: seq[uint8]
    glyphs*: array[128, GlyphInfo]
    fallback*: GlyphInfo

  WgpuBackend* = object
    instance*: WgpuInstance
    surface*: WgpuSurface
    adapter*: WgpuAdapter
    device*: WgpuDevice
    queue*: WgpuQueue
    rectPipeline*: WgpuRenderPipeline
    textPipeline*: WgpuRenderPipeline
    textBindGroupLayout*: WgpuBindGroupLayout
    rectPipelineLayout*: WgpuPipelineLayout
    textPipelineLayout*: WgpuPipelineLayout
    vertexBuffer*: WgpuBuffer
    indexBuffer*: WgpuBuffer
    atlasTexture*: WgpuTexture
    atlasTextureView*: WgpuTextureView
    atlasSampler*: WgpuSampler
    atlasBindGroup*: WgpuBindGroup
    textAtlas*: TextAtlas
    vertexBufferSize*: uint64
    indexBufferSize*: uint64
    width*: uint32
    height*: uint32
    surfaceFormat*: uint32
    surfaceAlphaMode*: uint32

  Renderer* = object
    backend*: WgpuBackend
