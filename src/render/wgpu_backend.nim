import wgpu
import wgpu/extras/helpers
import wgpu/extras/shaders
import wgpu/extras/strings
import ../types/core as core_types
import ../types/render_values
import text_atlas

# Cast helpers — keep wgpu types confined to this module.
func inst(b: WgpuBackend): wgpu.Instance =
  cast[wgpu.Instance](b.instance)
func surf(b: WgpuBackend): wgpu.Surface =
  cast[wgpu.Surface](b.surface)
func adpt(b: WgpuBackend): wgpu.Adapter =
  cast[wgpu.Adapter](b.adapter)
func dev(b: WgpuBackend): wgpu.Device =
  cast[wgpu.Device](b.device)
func que(b: WgpuBackend): wgpu.Queue =
  cast[wgpu.Queue](b.queue)
func vbuf(b: WgpuBackend): wgpu.Buffer =
  cast[wgpu.Buffer](b.vertexBuffer)
func ibuf(b: WgpuBackend): wgpu.Buffer =
  cast[wgpu.Buffer](b.indexBuffer)
func atlasTex(b: WgpuBackend): wgpu.Texture =
  cast[wgpu.Texture](b.atlasTexture)
func atlasView(b: WgpuBackend): wgpu.TextureView =
  cast[wgpu.TextureView](b.atlasTextureView)
func atlasSampler(b: WgpuBackend): wgpu.Sampler =
  cast[wgpu.Sampler](b.atlasSampler)
func atlasBg(b: WgpuBackend): wgpu.BindGroup =
  cast[wgpu.BindGroup](b.atlasBindGroup)
func textBgl(b: WgpuBackend): wgpu.BindGroupLayout =
  cast[wgpu.BindGroupLayout](b.textBindGroupLayout)
func rectLayout(b: WgpuBackend): wgpu.PipelineLayout =
  cast[wgpu.PipelineLayout](b.rectPipelineLayout)
func textLayout(b: WgpuBackend): wgpu.PipelineLayout =
  cast[wgpu.PipelineLayout](b.textPipelineLayout)
func rectPipe(b: WgpuBackend): wgpu.RenderPipeline =
  cast[wgpu.RenderPipeline](b.rectPipeline)
func textPipe(b: WgpuBackend): wgpu.RenderPipeline =
  cast[wgpu.RenderPipeline](b.textPipeline)

type
  QuadVertex = object
    x, y: float32
    u, v: float32
    r, g, b, a: float32

  QuadBatch = object
    vertices: seq[QuadVertex]
    indices: seq[uint32]
    rectIndexCount: uint32
    textIndexCount: uint32

const
  RectShader = staticRead("shaders/rect.wgsl")
  TextShader = staticRead("shaders/text.wgsl")

proc clipX(b: WgpuBackend, x: float32): float32 =
  (x / max(1'u32, b.width).float32) * 2.0'f32 - 1.0'f32

proc clipY(b: WgpuBackend, y: float32): float32 =
  1.0'f32 - (y / max(1'u32, b.height).float32) * 2.0'f32

proc appendQuad(
    batch: var QuadBatch,
    backend: WgpuBackend,
    x, y, w, h, u0, v0, u1, v1: float32,
    color: core_types.Color,
) =
  if w <= 0 or h <= 0 or color.a <= 0:
    return
  let base = batch.vertices.len.uint32
  batch.vertices.add QuadVertex(
    x: backend.clipX(x),
    y: backend.clipY(y),
    u: u0,
    v: v0,
    r: color.r,
    g: color.g,
    b: color.b,
    a: color.a,
  )
  batch.vertices.add QuadVertex(
    x: backend.clipX(x + w),
    y: backend.clipY(y),
    u: u1,
    v: v0,
    r: color.r,
    g: color.g,
    b: color.b,
    a: color.a,
  )
  batch.vertices.add QuadVertex(
    x: backend.clipX(x + w),
    y: backend.clipY(y + h),
    u: u1,
    v: v1,
    r: color.r,
    g: color.g,
    b: color.b,
    a: color.a,
  )
  batch.vertices.add QuadVertex(
    x: backend.clipX(x),
    y: backend.clipY(y + h),
    u: u0,
    v: v1,
    r: color.r,
    g: color.g,
    b: color.b,
    a: color.a,
  )
  batch.indices.add base + 0
  batch.indices.add base + 1
  batch.indices.add base + 2
  batch.indices.add base + 0
  batch.indices.add base + 2
  batch.indices.add base + 3

proc appendRect(batch: var QuadBatch, backend: WgpuBackend, cmd: NilDrawCmd) =
  let before = batch.indices.len
  batch.appendQuad(backend, cmd.x, cmd.y, cmd.w, cmd.h, 0, 0, 1, 1, cmd.color)
  batch.rectIndexCount += uint32(batch.indices.len - before)

proc appendText(batch: var QuadBatch, backend: WgpuBackend, cmd: NilDrawCmd) =
  var x = cmd.x
  let before = batch.indices.len
  for rune in glyphRunes(cmd.text):
    let glyph = backend.textAtlas.glyphFor(rune)
    batch.appendQuad(
      backend, x, cmd.y, glyph.w, glyph.h, glyph.u0, glyph.v0, glyph.u1, glyph.v1,
      cmd.color,
    )
    x += glyph.advance
  batch.textIndexCount += uint32(batch.indices.len - before)

proc buildBatch(backend: WgpuBackend, drawList: NilDrawList): QuadBatch =
  for cmd in drawList.cmds:
    if cmd.kind == dcRect:
      result.appendRect(backend, cmd)
  for cmd in drawList.cmds:
    if cmd.kind == dcTextRun:
      result.appendText(backend, cmd)

proc onAdapterRequest(
    status: RequestAdapterStatus,
    adapter: wgpu.Adapter,
    msg: StringView,
    userdata1: pointer,
    userdata2: pointer,
) {.cdecl.} =
  cast[ptr WgpuAdapter](userdata1)[] = cast[WgpuAdapter](adapter)

proc onDeviceRequest(
    status: RequestDeviceStatus,
    device: wgpu.Device,
    msg: StringView,
    userdata1: pointer,
    userdata2: pointer,
) {.cdecl.} =
  cast[ptr WgpuDevice](userdata1)[] = cast[WgpuDevice](device)

proc buildSurfaceConfig(b: WgpuBackend): SurfaceConfiguration =
  SurfaceConfiguration(
    device: b.dev(),
    format: cast[TextureFormat](b.surfaceFormat),
    usage: TextureUsage_RenderAttachment,
    width: b.width,
    height: b.height,
    alphaMode: cast[CompositeAlphaMode](b.surfaceAlphaMode),
    presentMode: PresentMode.Fifo,
  )

proc applyConfig(b: WgpuBackend) =
  var cfg = b.buildSurfaceConfig()
  b.surf().configure(cfg.addr)

proc makeShader(device: wgpu.Device, code, label: string): wgpu.ShaderModule =
  var shaderDesc = wgsl.toDescriptor(code, label = label)
  result = device.create(shaderDesc.addr)
  doAssert result != nil, "failed to create " & label

proc premulBlend(): BlendState =
  let component = BlendComponent(
    operation: BlendOperation.Add,
    srcFactor: BlendFactor.One,
    dstFactor: BlendFactor.OneMinusSrcAlpha,
  )
  BlendState(color: component, alpha: component)

proc makePipeline(
    device: wgpu.Device,
    layout: wgpu.PipelineLayout,
    shader: wgpu.ShaderModule,
    format: TextureFormat,
    label: string,
): wgpu.RenderPipeline =
  var attrs = [
    VertexAttribute(format: VertexFormat.Float32x2, offset: 0, shaderLocation: 0),
    VertexAttribute(
      format: VertexFormat.Float32x2,
      offset: 2'u64 * sizeof(float32).uint64,
      shaderLocation: 1,
    ),
    VertexAttribute(
      format: VertexFormat.Float32x4,
      offset: 4'u64 * sizeof(float32).uint64,
      shaderLocation: 2,
    ),
  ]
  var vertexLayout = VertexBufferLayout(
    stepMode: VertexStepMode.Vertex,
    arrayStride: sizeof(QuadVertex).uint64,
    attributeCount: attrs.len.csize_t,
    attributes: attrs[0].addr,
  )
  var blend = premulBlend()
  var target =
    ColorTargetState(format: format, blend: blend.addr, writeMask: ColorWriteMask_All)
  var fragment = FragmentState(
    module: shader,
    entryPoint: "fs_main".toStringView(),
    targetCount: 1,
    targets: target.addr,
  )
  result = device.create(
    vaddr RenderPipelineDescriptor(
      label: label.toStringView(),
      layout: layout,
      vertex: VertexState(
        module: shader,
        entryPoint: "vs_main".toStringView(),
        bufferCount: 1,
        buffers: vertexLayout.addr,
      ),
      primitive: PrimitiveState(
        topology: PrimitiveTopology.TriangleList,
        stripIndexFormat: IndexFormat.Undefined,
        frontFace: FrontFace.CCW,
        cullMode: CullMode.None,
      ),
      multisample:
        MultisampleState(count: 1, mask: uint32.high, alphaToCoverageEnabled: 0),
      fragment: fragment.addr,
    )
  )
  doAssert result != nil, "failed to create render pipeline"

proc initPipelines(b: var WgpuBackend) =
  let rectShader = b.dev().makeShader(RectShader, "nilrack rect shader")
  let textShader = b.dev().makeShader(TextShader, "nilrack text shader")

  let rectLayout = b.dev().create(
      vaddr PipelineLayoutDescriptor(
        label: "nilrack rect pipeline layout".toStringView(),
        bindGroupLayoutCount: 0,
        bindGroupLayouts: nil,
      )
    )
  doAssert rectLayout != nil, "failed to create rect pipeline layout"
  b.rectPipelineLayout = cast[WgpuPipelineLayout](rectLayout)

  var bglEntries = [
    BindGroupLayoutEntry(
      binding: 0,
      visibility: ShaderStage_Fragment,
      texture: TextureBindingLayout(
        sampleType: TextureSampleType.Float,
        viewDimension: TextureViewDimension.D2D,
        multisampled: 0,
      ),
    ),
    BindGroupLayoutEntry(
      binding: 1,
      visibility: ShaderStage_Fragment,
      sampler: SamplerBindingLayout(`type`: SamplerBindingType.Filtering),
    ),
  ]
  let textBgl = b.dev().createLayout(
      vaddr BindGroupLayoutDescriptor(
        label: "nilrack text bind group layout".toStringView(),
        entryCount: bglEntries.len.csize_t,
        entries: bglEntries[0].addr,
      )
    )
  doAssert textBgl != nil, "failed to create text bind group layout"
  b.textBindGroupLayout = cast[WgpuBindGroupLayout](textBgl)

  var textBglLocal = textBgl
  let textLayout = b.dev().create(
      vaddr PipelineLayoutDescriptor(
        label: "nilrack text pipeline layout".toStringView(),
        bindGroupLayoutCount: 1,
        bindGroupLayouts: textBglLocal.addr,
      )
    )
  doAssert textLayout != nil, "failed to create text pipeline layout"
  b.textPipelineLayout = cast[WgpuPipelineLayout](textLayout)

  let surfaceFormat = cast[TextureFormat](b.surfaceFormat)
  b.rectPipeline = cast[WgpuRenderPipeline](b.dev().makePipeline(
    rectLayout, rectShader, surfaceFormat, "nilrack rect pipeline"
  ))
  b.textPipeline = cast[WgpuRenderPipeline](b.dev().makePipeline(
    textLayout, textShader, surfaceFormat, "nilrack text pipeline"
  ))
  rectShader.release()
  textShader.release()

proc initTextAtlasTexture(b: var WgpuBackend) =
  b.textAtlas = buildTextAtlas()
  let texSize = Extent3D(
    width: b.textAtlas.width, height: b.textAtlas.height, depthOrArrayLayers: 1
  )
  let texture = b.dev().create(
      vaddr TextureDescriptor(
        label: "nilrack text atlas".toStringView(),
        usage: TextureUsage_CopyDst or TextureUsage_TextureBinding,
        dimension: TextureDimension.D2D,
        size: texSize,
        format: TextureFormat.RGBA8Unorm,
        mipLevelCount: 1,
        sampleCount: 1,
      )
    )
  doAssert texture != nil, "failed to create text atlas texture"
  b.atlasTexture = cast[WgpuTexture](texture)

  var dst = TexelCopyTextureInfo(
    texture: texture,
    mipLevel: 0,
    origin: Origin3D(x: 0, y: 0, z: 0),
    aspect: TextureAspect.All,
  )
  var src = TexelCopyBufferLayout(
    offset: 0, bytesPerRow: b.textAtlas.width * 4, rowsPerImage: b.textAtlas.height
  )
  b.que().write(
    dst.addr,
    b.textAtlas.pixels[0].addr,
    b.textAtlas.pixels.len.csize_t,
    src.addr,
    texSize.addr,
  )

  let view = texture.create(
    vaddr TextureViewDescriptor(
      label: "nilrack text atlas view".toStringView(),
      format: TextureFormat.RGBA8Unorm,
      dimension: TextureViewDimension.D2D,
      baseMipLevel: 0,
      mipLevelCount: 1,
      baseArrayLayer: 0,
      arrayLayerCount: 1,
      aspect: TextureAspect.All,
      usage: TextureUsage_TextureBinding,
    )
  )
  doAssert view != nil, "failed to create text atlas view"
  b.atlasTextureView = cast[WgpuTextureView](view)

  let sampler = b.dev().create(
      vaddr SamplerDescriptor(
        label: "nilrack text atlas sampler".toStringView(),
        addressModeU: AddressMode.ClampToEdge,
        addressModeV: AddressMode.ClampToEdge,
        addressModeW: AddressMode.ClampToEdge,
        magFilter: FilterMode.Linear,
        minFilter: FilterMode.Linear,
        mipmapFilter: MipmapFilterMode.Nearest,
        lodMinClamp: 0,
        lodMaxClamp: 1,
        compare: CompareFunction.Undefined,
        maxAnisotropy: 1,
      )
    )
  doAssert sampler != nil, "failed to create text atlas sampler"
  b.atlasSampler = cast[WgpuSampler](sampler)

  var entries = [
    BindGroupEntry(binding: 0, textureView: view),
    BindGroupEntry(binding: 1, sampler: sampler),
  ]
  let bindGroup = b.dev().create(
      vaddr BindGroupDescriptor(
        label: "nilrack text atlas bind group".toStringView(),
        layout: b.textBgl(),
        entryCount: entries.len.csize_t,
        entries: entries[0].addr,
      )
    )
  doAssert bindGroup != nil, "failed to create text atlas bind group"
  b.atlasBindGroup = cast[WgpuBindGroup](bindGroup)

proc ensureBuffer(
    device: wgpu.Device,
    buffer: var WgpuBuffer,
    currentSize: var uint64,
    requiredSize: uint64,
    usage: BufferUsage,
    label: string,
) =
  if requiredSize == 0 or currentSize >= requiredSize:
    return
  if pointer(buffer) != nil:
    cast[wgpu.Buffer](buffer).release()
  let newSize = max(requiredSize, currentSize * 2 + 4096)
  let gpuBuffer = device.create(
    vaddr BufferDescriptor(
      label: label.toStringView(),
      usage: usage or BufferUsage_CopyDst,
      size: newSize,
      mappedAtCreation: 0,
    )
  )
  doAssert gpuBuffer != nil, "failed to create " & label
  buffer = cast[WgpuBuffer](gpuBuffer)
  currentSize = newSize

proc uploadBatch(b: var WgpuBackend, batch: QuadBatch) =
  if batch.vertices.len == 0 or batch.indices.len == 0:
    return
  let vertexBytes = uint64(batch.vertices.len * sizeof(QuadVertex))
  let indexBytes = uint64(batch.indices.len * sizeof(uint32))
  b.dev().ensureBuffer(
    b.vertexBuffer, b.vertexBufferSize, vertexBytes, BufferUsage_Vertex,
    "nilrack vertex buffer",
  )
  b.dev().ensureBuffer(
    b.indexBuffer, b.indexBufferSize, indexBytes, BufferUsage_Index,
    "nilrack index buffer",
  )
  b.que().write(b.vbuf(), 0, batch.vertices[0].unsafeAddr, vertexBytes.csize_t)
  b.que().write(b.ibuf(), 0, batch.indices[0].unsafeAddr, indexBytes.csize_t)

proc initWgpuBackend*(
    b: var WgpuBackend, display, wlSurface: pointer, width, height: uint32
) =
  b.width = width
  b.height = height

  let inst = wgpu.create(vaddr InstanceDescriptor())
  doAssert inst != nil, "failed to create WebGPU instance"
  b.instance = cast[WgpuInstance](inst)

  let surf = inst.create(
    vaddr SurfaceDescriptor(
      nextInChain: cast[ptr ChainedStruct](vaddr SurfaceSourceWaylandSurface(
        chain: ChainedStruct(next: nil, sType: SType.SurfaceSourceWaylandSurface),
        display: display,
        surface: wlSurface,
      ))
    )
  )
  doAssert surf != nil, "failed to create Wayland WebGPU surface"
  b.surface = cast[WgpuSurface](surf)

  var adpt: WgpuAdapter
  var adptFuture = inst.request(
    vaddr RequestAdapterOptions(
      compatibleSurface: surf,
      powerPreference: PowerPreference.HighPerformance,
      featureLevel: FeatureLevel.Core,
    ),
    RequestAdapterCallbackInfo(
      mode: CallbackMode.AllowSpontaneous,
      callback: onAdapterRequest,
      userdata1: adpt.addr,
    ),
  )
  var adptWait = FutureWaitInfo(future: adptFuture, completed: 0)
  doAssert inst.wait(1, adptWait.addr, high(uint64)) == Success
  doAssert pointer(adpt) != nil, "failed to request WebGPU adapter"
  b.adapter = adpt

  var dev: WgpuDevice
  var devFuture = b.adpt().request(
      vaddr DeviceDescriptor(
        defaultQueue: QueueDescriptor(),
        deviceLostCallbackInfo:
          DeviceLostCallbackInfo(mode: cast[cint](CallbackMode.AllowSpontaneous)),
      ),
      RequestDeviceCallbackInfo(
        mode: CallbackMode.AllowSpontaneous,
        callback: onDeviceRequest,
        userdata1: dev.addr,
      ),
    )
  var devWait = FutureWaitInfo(future: devFuture, completed: 0)
  doAssert inst.wait(1, devWait.addr, high(uint64)) == Success
  doAssert pointer(dev) != nil, "failed to request WebGPU device"
  b.device = dev

  b.queue = cast[WgpuQueue](b.dev().getQueue())

  var caps: SurfaceCapabilities
  doAssert surf.get(b.adpt(), caps.addr) == Success, "failed to get surface caps"
  b.surfaceFormat =
    cast[uint32](cast[ptr UncheckedArray[TextureFormat]](caps.formats)[0])
  b.surfaceAlphaMode =
    cast[uint32](cast[ptr UncheckedArray[CompositeAlphaMode]](caps.alphaModes)[0])
  caps.freeMembers()
  b.applyConfig()
  b.initPipelines()
  b.initTextAtlasTexture()

proc resizeWgpuBackend*(b: var WgpuBackend, width, height: uint32) =
  if width == 0 or height == 0:
    return
  b.width = width
  b.height = height
  b.applyConfig()

proc renderDrawList*(b: var WgpuBackend, drawList: NilDrawList) =
  let batch = b.buildBatch(drawList)
  b.uploadBatch(batch)

  var surfaceTex: SurfaceTexture
  b.surf().getCurrentTexture(surfaceTex.addr)

  case surfaceTex.status
  of SuccessOptimal, SuccessSuboptimal:
    discard
  of Timeout, Outdated, Lost:
    if surfaceTex.texture != nil:
      surfaceTex.texture.release()
    b.applyConfig()
    return
  else:
    stderr.writeLine "wgpu: getCurrentTexture failed: " & $surfaceTex.status
    return

  let view = surfaceTex.texture.create(nil)
  let encoder = b.dev().create(vaddr CommandEncoderDescriptor())

  let renderPass = encoder.begin(
    vaddr RenderPassDescriptor(
      colorAttachmentCount: 1,
      colorAttachments: vaddr RenderPassColorAttachment(
        view: view,
        loadOp: Clear,
        storeOp: Store,
        clearValue: wgpu.Color(r: 0.10, g: 0.10, b: 0.10, a: 1.0),
      ),
    )
  )
  if batch.indices.len > 0:
    renderPass.setVertexBuffer(0, b.vbuf(), 0, b.vertexBufferSize)
    renderPass.setIndexBuffer(b.ibuf(), IndexFormat.Uint32, 0, b.indexBufferSize)
    if batch.rectIndexCount > 0:
      renderPass.set(b.rectPipe())
      renderPass.drawIndexed(batch.rectIndexCount, 1, 0, 0, 0)
    if batch.textIndexCount > 0:
      renderPass.set(b.textPipe())
      renderPass.set(0, b.atlasBg(), 0, nil)
      renderPass.drawIndexed(batch.textIndexCount, 1, batch.rectIndexCount, 0, 0)
  renderPass.End()
  view.release()

  let cmdBuf = encoder.finish(vaddr CommandBufferDescriptor())
  encoder.release()
  b.que().submit(1, cmdBuf.addr)
  cmdBuf.release()

  discard b.surf().present()
  surfaceTex.texture.release()

proc renderClear*(b: var WgpuBackend) =
  let empty = NilDrawList()
  b.renderDrawList(empty)

proc shutdownWgpuBackend*(b: var WgpuBackend) =
  if pointer(b.indexBuffer) != nil:
    b.ibuf().release()
  if pointer(b.vertexBuffer) != nil:
    b.vbuf().release()
  if pointer(b.atlasBindGroup) != nil:
    b.atlasBg().release()
  if pointer(b.atlasSampler) != nil:
    b.atlasSampler().release()
  if pointer(b.atlasTextureView) != nil:
    b.atlasView().release()
  if pointer(b.atlasTexture) != nil:
    b.atlasTex().release()
  if pointer(b.textPipeline) != nil:
    b.textPipe().release()
  if pointer(b.rectPipeline) != nil:
    b.rectPipe().release()
  if pointer(b.textPipelineLayout) != nil:
    b.textLayout().release()
  if pointer(b.rectPipelineLayout) != nil:
    b.rectLayout().release()
  if pointer(b.textBindGroupLayout) != nil:
    b.textBgl().release()
  if pointer(b.queue) != nil:
    b.que().release()
  if pointer(b.device) != nil:
    b.dev().release()
  if pointer(b.adapter) != nil:
    b.adpt().release()
  if pointer(b.surface) != nil:
    b.surf().release()
  if pointer(b.instance) != nil:
    b.inst().release()
