import audio_values
import core
import model

const MaxGraphCompileErrors* = 64

type
  GraphCompileErrorKind* = enum
    gceCycleDetected
    gcePlanCapacityExceeded
    gceMissingRuntime
    gceUnsupportedRoutePolicy
    gceMissingPort
    gceDirectionMismatch
    gceKindMismatch

  GraphCompileError* = object
    kind*: GraphCompileErrorKind
    rackId*: RackId
    nodeId*: NodeId
    cableId*: CableId
    pluginId*: PluginId
    portId*: PortId
    routePolicy*: CableRoutePolicy

  GraphCompileReport* = object
    rackId*: RackId
    plan*: ProcessPlan
    errorCount*: uint32
    errors*: array[MaxGraphCompileErrors, GraphCompileError]
    errorOverflowed*: bool
