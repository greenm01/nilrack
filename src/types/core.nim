import std/tables

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
