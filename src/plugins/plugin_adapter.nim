import ../state/engine
import ../types/[core, plugin_values]

type PluginAttachResult* = object
  rackId*: RackId
  nodeId*: NodeId
  pluginId*: PluginId

proc attachPluginDescriptor*(
    m: var NilrackModel, descriptor: PluginDescriptor
): PluginAttachResult =
  let rackId = m.firstRackIdOrCreateDefault()
  let nodeId = m.nodeCreate(rackId, nkPlugin, descriptor.name)
  m.nodeMove(nodeId, 64.0'f32, 72.0'f32)
  m.nodeResize(
    nodeId,
    340.0'f32,
    max(180.0'f32, 78.0'f32 + descriptor.params.len.float32 * 24.0'f32),
  )

  let pluginId = m.pluginAttachToNode(
    nodeId, descriptor.api, descriptor.path, descriptor.uri, descriptor.name,
    descriptor.vendor, descriptor.version, descriptor.hasState,
  )

  for i, port in descriptor.ports:
    let portId = m.portCreate(
      nodeId, port.kind, port.direction, port.index, port.name, port.index,
      port.externalId, port.channelCount, port.isMain,
    )
    m.portBindExternalKey(pluginId, uint32(i), portId)

  for param in descriptor.params:
    let paramId = m.paramCreate(
      nodeId, param.name, param.minVal, param.maxVal, param.defaultVal,
      param.currentVal, param.modulePath, param.index, param.externalId,
      param.displayText, param.stepped, param.hidden, param.readonly, param.bypass,
      param.automatable,
    )
    m.paramBindExternalKey(pluginId, param.index, paramId)

  PluginAttachResult(rackId: rackId, nodeId: nodeId, pluginId: pluginId)
