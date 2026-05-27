import core

type ProcessPlan* = object
  nodeOrder*: seq[NodeId]
