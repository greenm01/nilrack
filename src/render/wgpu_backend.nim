import wgpu
import wgpu/extras/helpers
import ../types/render_values

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

proc resizeWgpuBackend*(b: var WgpuBackend, width, height: uint32) =
  if width == 0 or height == 0:
    return
  b.width = width
  b.height = height
  b.applyConfig()

proc renderClear*(b: var WgpuBackend) =
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
        clearValue: Color(r: 0.10, g: 0.10, b: 0.10, a: 1.0),
      ),
    )
  )
  renderPass.End()
  view.release()

  let cmdBuf = encoder.finish(vaddr CommandBufferDescriptor())
  encoder.release()
  b.que().submit(1, cmdBuf.addr)
  cmdBuf.release()

  discard b.surf().present()
  surfaceTex.texture.release()

proc shutdownWgpuBackend*(b: var WgpuBackend) =
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
