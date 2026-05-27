import std/tables
import ../types/core
import ../types/model as typeModel
import ../types/audio_values

export typeModel

type NilrackModel* = object
  counters*: IdCounters

  racks*: EntityManager[RackId, RackData]
  nodes*: EntityManager[NodeId, NodeData]
  cables*: EntityManager[CableId, CableData]
  ports*: EntityManager[PortId, PortData]
  params*: EntityManager[ParamId, ParamData]
  plugins*: EntityManager[PluginId, PluginData]
  pluginUis*: EntityManager[PluginUiId, PluginUiData]
  renderSurfaces*: EntityManager[RenderSurfaceId, RenderSurfaceData]
  textures*: EntityManager[TextureId, TextureData]
  inputTargets*: EntityManager[InputTargetId, InputTargetData]

  nodesByRack*: Table[RackId, seq[NodeId]]
  cablesByRack*: Table[RackId, seq[CableId]]
  portsByNode*: Table[NodeId, seq[PortId]]
  paramsByNode*: Table[NodeId, seq[ParamId]]
  pluginByNode*: Table[NodeId, PluginId]
  uiByPlugin*: Table[PluginId, PluginUiId]
  nodeByPlugin*: Table[PluginId, NodeId]
  portByExternalKey*: Table[ExternalPortKey, PortId]
  paramByExternalKey*: Table[ExternalParamKey, ParamId]
  inputTargetByNode*: Table[NodeId, InputTargetId]

  processPlan*: ProcessPlan
