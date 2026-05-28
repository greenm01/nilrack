import std/hashes
import core

type
  NodeKind* = enum
    nkPlugin
    nkInput
    nkOutput

  PortKind* = enum
    pkAudio
    pkMidi
    pkCv

  PortDirection* = enum
    pdIn
    pdOut

  CableRoutePolicy* = enum
    crAuto
    crChannelMap
    crSumToMono
    crDropExtra
    crSelectChannel

  PluginApi* = enum
    paClap
    paLv2
    paVst3

  StateBlobRef* = object
    data*: seq[byte]

  RackData* = object
    id*: RackId
    name*: string
    rootNode*: NodeId
    sampleRate*: float64
    blockSize*: uint32

  NodeData* = object
    id*: NodeId
    rackId*: RackId
    kind*: NodeKind
    name*: string
    x*, y*: float32
    w*, h*: float32
    bypassed*: bool
    muted*: bool

  CableData* = object
    id*: CableId
    rackId*: RackId
    srcPort*: PortId
    dstPort*: PortId
    kind*: PortKind
    routePolicy*: CableRoutePolicy

  PortData* = object
    id*: PortId
    nodeId*: NodeId
    kind*: PortKind
    direction*: PortDirection
    channelIndex*: uint32
    name*: string
    externalIndex*: uint32
    externalId*: uint32
    channelCount*: uint32
    isMain*: bool

  ParamData* = object
    id*: ParamId
    nodeId*: NodeId
    name*: string
    modulePath*: string
    externalIndex*: uint32
    externalId*: uint32
    minVal*: float64
    maxVal*: float64
    defaultVal*: float64
    currentVal*: float64
    displayText*: string
    stepped*: bool
    hidden*: bool
    readonly*: bool
    bypass*: bool
    automatable*: bool

  PluginData* = object
    id*: PluginId
    nodeId*: NodeId
    api*: PluginApi
    path*: string
    uri*: string
    displayName*: string
    vendor*: string
    version*: string
    hasState*: bool
    stateRef*: StateBlobRef

  PluginUiData* = object
    id*: PluginUiId
    pluginId*: PluginId

  RenderSurfaceData* = object
    id*: RenderSurfaceId

  TextureData* = object
    id*: TextureId
    w*, h*: uint32

  InputTargetData* = object
    id*: InputTargetId
    nodeId*: NodeId
    x*, y*, w*, h*: float32

  ExternalPortKey* = object
    pluginId*: PluginId
    index*: uint32

  ExternalParamKey* = object
    pluginId*: PluginId
    index*: uint32

proc `==`*(a, b: ExternalPortKey): bool =
  a.pluginId == b.pluginId and a.index == b.index

proc `==`*(a, b: ExternalParamKey): bool =
  a.pluginId == b.pluginId and a.index == b.index

proc hash*(k: ExternalPortKey): Hash =
  hash((uint32(k.pluginId), k.index))

proc hash*(k: ExternalParamKey): Hash =
  hash((uint32(k.pluginId), k.index))
