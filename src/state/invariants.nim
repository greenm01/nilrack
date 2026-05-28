import std/[options, tables]

import ../types/core
import model
import entity_manager

proc checkInvariants*(m: NilrackModel): bool =
  if not m.racks.hasDenseIndex or not m.nodes.hasDenseIndex or not m.cables.hasDenseIndex or
      not m.channelMaps.hasDenseIndex or not m.ports.hasDenseIndex or
      not m.params.hasDenseIndex or not m.plugins.hasDenseIndex or
      not m.pluginUis.hasDenseIndex:
    return false
  for node in m.nodes.data:
    if not m.racks.contains(node.rackId):
      return false
  for cable in m.cables.data:
    if not m.racks.contains(cable.rackId):
      return false
    if not m.ports.contains(cable.srcPort):
      return false
    if not m.ports.contains(cable.dstPort):
      return false
    let src = m.ports.entity(cable.srcPort)
    let dst = m.ports.entity(cable.dstPort)
    if src.isNone or dst.isNone:
      return false
    if src.get.direction != pdOut or dst.get.direction != pdIn:
      return false
    if src.get.kind != dst.get.kind or src.get.kind != cable.kind:
      return false
    if cable.channelMapId != NullChannelMapId:
      let channelMap = m.channelMaps.entity(cable.channelMapId)
      if channelMap.isNone or channelMap.get.rackId != cable.rackId:
        return false
    if cable.routePolicy == crChannelMap and cable.channelMapId == NullChannelMapId:
      return false
  for channelMap in m.channelMaps.data:
    if not m.racks.contains(channelMap.rackId):
      return false
  for port in m.ports.data:
    if not m.nodes.contains(port.nodeId):
      return false
  for param in m.params.data:
    if not m.nodes.contains(param.nodeId):
      return false
  for plugin in m.plugins.data:
    if not m.nodes.contains(plugin.nodeId):
      return false
    if m.pluginByNode.getOrDefault(plugin.nodeId, NullPluginId) != plugin.id:
      return false
    if m.nodeByPlugin.getOrDefault(plugin.id, NullNodeId) != plugin.nodeId:
      return false
  for ui in m.pluginUis.data:
    if not m.plugins.contains(ui.pluginId):
      return false
    if m.uiByPlugin.getOrDefault(ui.pluginId, NullPluginUiId) != ui.id:
      return false
  for rackId, nodes in m.nodesByRack.pairs:
    if not m.racks.contains(rackId):
      return false
    for nodeId in nodes:
      let node = m.nodes.entity(nodeId)
      if node.isNone or node.get.rackId != rackId:
        return false
  for rackId, cables in m.cablesByRack.pairs:
    if not m.racks.contains(rackId):
      return false
    for cableId in cables:
      let cable = m.cables.entity(cableId)
      if cable.isNone or cable.get.rackId != rackId:
        return false
  for rackId, channelMaps in m.channelMapsByRack.pairs:
    if not m.racks.contains(rackId):
      return false
    for channelMapId in channelMaps:
      let channelMap = m.channelMaps.entity(channelMapId)
      if channelMap.isNone or channelMap.get.rackId != rackId:
        return false
  for nodeId, ports in m.portsByNode.pairs:
    if not m.nodes.contains(nodeId):
      return false
    for portId in ports:
      let port = m.ports.entity(portId)
      if port.isNone or port.get.nodeId != nodeId:
        return false
  for nodeId, params in m.paramsByNode.pairs:
    if not m.nodes.contains(nodeId):
      return false
    for paramId in params:
      let param = m.params.entity(paramId)
      if param.isNone or param.get.nodeId != nodeId:
        return false
  true
