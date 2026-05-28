import std/[options, tables]
import ../types/[core, audio_values]
import ../systems/graph_process_plan
import entity_manager
import model

proc compileProcessPlan*(m: NilrackModel): ProcessPlan =
  result = ProcessPlan()
  for rack in m.racks.data:
    for nodeId in m.nodesByRack.getOrDefault(rack.id, @[]):
      discard result.addPlanNode(nodeId)
      if not m.pluginByNode.hasKey(nodeId):
        continue
      let pluginId = m.pluginByNode[nodeId]
      discard result.addPluginTarget(pluginId)
      for paramId in m.paramsByNode.getOrDefault(nodeId, @[]):
        discard result.addParamTarget(pluginId, paramId)
      for portId in m.portsByNode.getOrDefault(nodeId, @[]):
        let port = m.ports.entity(portId)
        if port.isSome and port.get.kind != pkAudio and port.get.direction == pdIn:
          discard result.addEventPortTarget(portId)
