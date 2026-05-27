import std/[hashes, tables]

type
  RackId* = distinct uint32
  NodeId* = distinct uint32
  CableId* = distinct uint32
  PortId* = distinct uint32
  ParamId* = distinct uint32
  PluginId* = distinct uint32
  PluginUiId* = distinct uint32
  AudioBackendId* = distinct uint32
  RenderSurfaceId* = distinct uint32
  TextureId* = distinct uint32
  InputTargetId* = distinct uint32

  ClapPluginHandle* = distinct pointer
  Lv2InstanceHandle* = distinct pointer
  Vst3InstanceHandle* = distinct pointer
  JackClientHandle* = distinct pointer
  WaylandSurfaceHandle* = distinct pointer
  WgpuTextureHandle* = distinct pointer

  Rect* = object
    x*, y*, w*, h*: float32

  Color* = object
    r*, g*, b*, a*: float32

  EntityManager*[ID, T] = object
    data*: seq[T]
    index*: Table[ID, int]

  IdCounters* = object
    nextRackId*: uint32
    nextNodeId*: uint32
    nextCableId*: uint32
    nextPortId*: uint32
    nextParamId*: uint32
    nextPluginId*: uint32
    nextPluginUiId*: uint32
    nextAudioBackendId*: uint32
    nextRenderSurfaceId*: uint32
    nextTextureId*: uint32
    nextInputTargetId*: uint32

const
  NullRackId* = RackId(0)
  NullNodeId* = NodeId(0)
  NullCableId* = CableId(0)
  NullPortId* = PortId(0)
  NullParamId* = ParamId(0)
  NullPluginId* = PluginId(0)
  NullPluginUiId* = PluginUiId(0)
  NullAudioBackendId* = AudioBackendId(0)
  NullRenderSurfaceId* = RenderSurfaceId(0)
  NullTextureId* = TextureId(0)
  NullInputTargetId* = InputTargetId(0)

proc `==`*(a, b: RackId): bool {.borrow.}
proc `==`*(a, b: NodeId): bool {.borrow.}
proc `==`*(a, b: CableId): bool {.borrow.}
proc `==`*(a, b: PortId): bool {.borrow.}
proc `==`*(a, b: ParamId): bool {.borrow.}
proc `==`*(a, b: PluginId): bool {.borrow.}
proc `==`*(a, b: PluginUiId): bool {.borrow.}
proc `==`*(a, b: AudioBackendId): bool {.borrow.}
proc `==`*(a, b: RenderSurfaceId): bool {.borrow.}
proc `==`*(a, b: TextureId): bool {.borrow.}
proc `==`*(a, b: InputTargetId): bool {.borrow.}

proc `<`*(a, b: RackId): bool {.borrow.}
proc `<`*(a, b: NodeId): bool {.borrow.}
proc `<`*(a, b: CableId): bool {.borrow.}
proc `<`*(a, b: PortId): bool {.borrow.}
proc `<`*(a, b: ParamId): bool {.borrow.}
proc `<`*(a, b: PluginId): bool {.borrow.}
proc `<`*(a, b: PluginUiId): bool {.borrow.}
proc `<`*(a, b: AudioBackendId): bool {.borrow.}
proc `<`*(a, b: RenderSurfaceId): bool {.borrow.}
proc `<`*(a, b: TextureId): bool {.borrow.}
proc `<`*(a, b: InputTargetId): bool {.borrow.}

proc `$`*(id: RackId): string {.borrow.}
proc `$`*(id: NodeId): string {.borrow.}
proc `$`*(id: CableId): string {.borrow.}
proc `$`*(id: PortId): string {.borrow.}
proc `$`*(id: ParamId): string {.borrow.}
proc `$`*(id: PluginId): string {.borrow.}
proc `$`*(id: PluginUiId): string {.borrow.}
proc `$`*(id: AudioBackendId): string {.borrow.}
proc `$`*(id: RenderSurfaceId): string {.borrow.}
proc `$`*(id: TextureId): string {.borrow.}
proc `$`*(id: InputTargetId): string {.borrow.}

proc hash*(id: RackId): Hash =
  hash(uint32(id))

proc hash*(id: NodeId): Hash =
  hash(uint32(id))

proc hash*(id: CableId): Hash =
  hash(uint32(id))

proc hash*(id: PortId): Hash =
  hash(uint32(id))

proc hash*(id: ParamId): Hash =
  hash(uint32(id))

proc hash*(id: PluginId): Hash =
  hash(uint32(id))

proc hash*(id: PluginUiId): Hash =
  hash(uint32(id))

proc hash*(id: AudioBackendId): Hash =
  hash(uint32(id))

proc hash*(id: RenderSurfaceId): Hash =
  hash(uint32(id))

proc hash*(id: TextureId): Hash =
  hash(uint32(id))

proc hash*(id: InputTargetId): Hash =
  hash(uint32(id))
