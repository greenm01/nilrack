import model
import entity_manager

proc checkInvariants*(m: NilrackModel): bool =
  for node in m.nodes.data:
    if not m.racks.contains(node.rackId):
      return false
  for cable in m.cables.data:
    if not m.ports.contains(cable.srcPort):
      return false
    if not m.ports.contains(cable.dstPort):
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
  true
