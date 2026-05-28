import std/tables
import ../types/[core, audio_values]
import model

proc compileProcessPlan*(m: NilrackModel): ProcessPlan =
  result = ProcessPlan()
  for rack in m.racks.data:
    for nodeId in m.nodesByRack.getOrDefault(rack.id, @[]):
      discard result.addPlanNode(nodeId)
