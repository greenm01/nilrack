import ../types/core

proc nextRaw(counter: var uint32): uint32 =
  if counter == high(uint32):
    raise newException(OverflowDefect, "exhausted nilrack logical IDs")
  inc counter
  if counter == 0:
    raise newException(OverflowDefect, "logical ID counter wrapped to zero")
  counter

proc generateRackId*(counters: var IdCounters): RackId =
  RackId(nextRaw(counters.nextRackId))

proc generateNodeId*(counters: var IdCounters): NodeId =
  NodeId(nextRaw(counters.nextNodeId))

proc generateCableId*(counters: var IdCounters): CableId =
  CableId(nextRaw(counters.nextCableId))

proc generateChannelMapId*(counters: var IdCounters): ChannelMapId =
  ChannelMapId(nextRaw(counters.nextChannelMapId))

proc generatePortId*(counters: var IdCounters): PortId =
  PortId(nextRaw(counters.nextPortId))

proc generateParamId*(counters: var IdCounters): ParamId =
  ParamId(nextRaw(counters.nextParamId))

proc generatePluginId*(counters: var IdCounters): PluginId =
  PluginId(nextRaw(counters.nextPluginId))

proc generatePluginUiId*(counters: var IdCounters): PluginUiId =
  PluginUiId(nextRaw(counters.nextPluginUiId))

proc generateAudioBackendId*(counters: var IdCounters): AudioBackendId =
  AudioBackendId(nextRaw(counters.nextAudioBackendId))

proc generateRenderSurfaceId*(counters: var IdCounters): RenderSurfaceId =
  RenderSurfaceId(nextRaw(counters.nextRenderSurfaceId))

proc generateTextureId*(counters: var IdCounters): TextureId =
  TextureId(nextRaw(counters.nextTextureId))

proc generateInputTargetId*(counters: var IdCounters): InputTargetId =
  InputTargetId(nextRaw(counters.nextInputTargetId))
