# nilrack Data-Oriented Design

`nilrack` should be built as a data-oriented machine. The rack is not an
object graph. Plugins do not own cables. UI widgets do not own engine state.
The audio callback does not chase application objects.

Tables own data. IDs connect tables. Operations mutate the model. Systems read
through queries and write through operations. Snapshots cross thread and API
boundaries.

This follows the same basic shape as Triad and `wayembed`: passive records,
dense storage, explicit indexes, narrow facades, and boring invariants.

## Core Rule

Separate data from code.

`types/` defines records, IDs, enums, flags, and small value types. `state/`
owns storage, ID counters, indexes, queries, snapshots, and invariants.
`entities/` applies cross-table mutations. `systems/` owns policy and behavior.
Platform, renderer, audio, plugin, and embedding modules adapt external APIs to
the model.

```text
external event
        |
        v
platform/plugin/audio adapter
        |
        +-- hot direct call where safe
        |
        +-- model mutation
                |
                v
             operation
                |
                v
          indexed state tables
```

External handles are fields in records. They are not the source of truth for
relationships.

## Module Layout

The first shape should stay close to Triad's Nim layout.

```text
src/
  types/
    core.nim          ids, handles, flags, Rect, Color, EntityManager
    model.nim         passive records
    audio_values.nim  audio formats, ports, buffers, meters
    plugin_values.nim plugin metadata, params, state refs
    render_values.nim draw commands, textures, renderer caps
    ui_values.nim     UI state records and hit targets

  state/
    entity_manager.nim
    id_gen.nim
    model.nim         NilrackModel
    queries.nim
    iterators.nim
    snapshot.nim
    invariants.nim
    engine.nim        facade exported to systems and adapters

  entities/
    rack_ops.nim
    node_ops.nim
    cable_ops.nim
    plugin_ops.nim
    param_ops.nim
    ui_ops.nim
    audio_ops.nim

  systems/
    graph_compile.nim
    graph_process_plan.nim
    plugin_scan.nim
    plugin_lifecycle.nim
    param_mapping.nim
    ui_layout.nim
    ui_hit_test.nim
    render_projection.nim
    session_io.nim

  audio/
    jack_backend.nim
    process_callback.nim
    rt_queue.nim

  plugins/
    clap_host.nim
    lv2_host.nim
    vst3_host.nim
    plugin_adapter.nim

  render/
    renderer.nim
    draw_list.nim
    wgpu_backend.nim
    software_backend.nim

  platform/
    wayland_app.nim
    input.nim

  embed/
    wayembed_host.nim
    xwayland_bridge.nim
```

The names can change. The boundary should not. Types stay passive. State owns
tables. Entity operations maintain indexes. Systems express behavior. Adapters
translate external APIs.

## IDs

Every long-lived thing gets a typed logical ID.

```nim
type
  RackId* = distinct uint32
  NodeId* = distinct uint32
  CableId* = distinct uint32
  PortId* = distinct uint32
  ParamId* = distinct uint32
  PluginId* = distinct uint32
  PluginUiId* = distinct uint32
  AudioBackendId* = distinct uint32
  RenderSurfaceId* = distinct uint32
  TextureId* = distinct uint32
  InputTargetId* = distinct uint32
```

ID `0` is null. Counters increment before issue. Zero is never a valid answer.
Do not reuse IDs during one process lifetime unless a generation scheme makes
reuse explicit.

External IDs and handles get their own types:

```nim
type
  ClapPluginHandle* = distinct pointer
  Lv2InstanceHandle* = distinct pointer
  Vst3InstanceHandle* = distinct pointer
  JackClientHandle* = distinct pointer
  WaylandSurfaceHandle* = distinct pointer
  WgpuTextureHandle* = distinct pointer
```

These handles are lookup keys or payload fields. They do not define ownership.
`NodeId`, `PluginId`, `PortId`, and `PluginUiId` define ownership.

## Storage

Use dense storage for entities.

```text
EntityManager(ID, T)
  data[]          dense records
  index           ID -> dense index
```

Deletion may use swap-and-pop. Callers must not depend on physical position.
If order matters, store it explicitly in a relationship table or sorted view.

The entity manager only does CRUD:

```text
insert
delete
contains
get
getMutable
items
```

It does not understand plugins, cables, graph compilation, audio ports, or UI
policy.

## Model

`NilrackModel` is the database.

```nim
type
  NilrackModel* = object
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
```

Indexes serve hot lookups and relationship traversal. Systems should not scan
all plugins to find one node. Audio should not scan all ports to find the ports
for a node.

## Core Records

Records are data, not behavior.

```nim
type
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

  PortData* = object
    id*: PortId
    nodeId*: NodeId
    kind*: PortKind
    direction*: PortDirection
    channelIndex*: uint32
    name*: string

  PluginData* = object
    id*: PluginId
    nodeId*: NodeId
    api*: PluginApi
    path*: string
    uri*: string
    displayName*: string
    stateRef*: StateBlobRef
```

Do not add methods like `node.connect()` or `plugin.activate()` to these
records. Those belong in operations and systems.

## Operations

All cross-table mutation goes through operations.

```text
rackCreate
rackDestroy
nodeCreate
nodeDestroy
nodeMove
cableCreate
cableDestroy
pluginAttachToNode
pluginDetach
paramCreate
paramSetNormalized
pluginUiCreate
pluginUiDestroy
audioBackendAttach
renderSurfaceCreate
inputTargetCreate
```

Operations maintain every index they touch. If destroying a plugin removes a
node's params, ports, UI, state blob, and process-plan entry, one operation owns
that teardown.

Manual cross-table mutation in a system is a bug. Manual index mutation in an
adapter is a bug.

## Systems

Systems hold behavior. They read through queries and iterators. They mutate
through operations.

Examples:

- graph compilation
- process-plan construction
- port compatibility checks
- plugin lifecycle policy
- parameter smoothing policy
- UI layout
- hit testing
- render projection
- session load/save
- XWayland bridge policy

Systems do not own storage. They do not reach into entity manager internals.

## Queries and Iterators

Queries answer questions without mutation.

```text
node(id)
pluginForNode(node_id)
portsForNode(node_id)
paramsForNode(node_id)
cablesForRack(rack_id)
canConnect(src_port, dst_port)
effectiveNodeBypass(node_id)
pluginUiForPlugin(plugin_id)
inputTargetAt(x, y)
```

Iterators expose traversal without allocation where practical.

```text
nodesInRack(rack_id)
cablesInRack(rack_id)
audioPortsForNode(node_id)
paramsForNode(node_id)
visibleInputTargets()
```

Allocation-returning helpers are acceptable for snapshots, diagnostics, plugin
scanning results, and tests. Hot audio, input, and render paths should prefer
borrowed views, fixed buffers, or preallocated output arrays.

## Realtime Model

The realtime audio thread must not use the application model directly. It uses
a compiled process snapshot.

```text
NilrackModel
    |
    | graph_compile system
    v
ProcessPlan
    |
    | atomic publish outside callback
    v
audio callback reads immutable plan
```

`ProcessPlan` contains only data the callback needs:

- ordered node list
- plugin process handles
- port buffer bindings
- event queues
- parameter slots
- bypass/mute flags
- meter outputs

The callback must not allocate, log, take locks, scan plugins, open files,
modify UI state, or call high-level Nim code that may allocate.

UI-to-audio changes cross preallocated queues. Audio-to-UI data crosses through
snapshots: meters, XRuns, transport state, plugin process errors, and graph
health.

## Render Model

The renderer consumes data. It does not own UI state.

```text
NilrackModel
    |
    | ui_layout + render_projection
    v
NilDrawList
    |
    +--> wgpu backend
    |
    +--> software debug backend
```

`NilDrawList` is the stable rendering model. `wgpu-native` is a backend. The UI
layer does not call WGPU directly.

Draw commands should be flat, batchable records:

- rect
- rounded rect
- border
- line/polyline
- text run
- image
- clip push/pop
- bezier cable
- meter batch

The renderer may keep GPU resources, pipelines, and staging buffers. Those
resources are indexed by IDs in the model or renderer state. They are not the
source of truth for visible UI.

## Plugin Adapters

CLAP, LV2, and VST3 are adapters into one internal plugin model.

Each adapter translates format-specific data into:

- plugin descriptor
- ports
- params
- state blob
- process call
- UI capability record
- error record

The rack graph should not know whether a node came from CLAP, LV2, or VST3.
Format-specific code belongs in adapter modules and state records that carry
explicit `PluginApi` tags.

Plugin UI support follows the same rule:

- native Wayland UI through `wayembed`
- XWayland UI through the bridge
- generated parameter UI from internal params

The generated UI is data-driven and always available when parameters exist.

## Effects

Some operations need deferred work. Use an effect queue instead of doing that
work inside the mutation.

Examples:

```text
EffectGraphDirty(rack_id)
EffectProcessPlanDirty(rack_id)
EffectPluginScanRequested(path)
EffectPluginUiOpenRequested(plugin_id)
EffectRendererTextureDirty(texture_id)
EffectSessionDirty
EffectDiagnosticsDirty
```

Effects fire after the current update step. They may schedule plugin loading,
graph recompilation, renderer uploads, or UI notifications. They must not run
inside the audio callback.

## Snapshots

Boundaries get snapshots.

Use snapshots for:

- UI views over engine state
- audio-to-UI meter publication
- diagnostics
- tests
- IPC
- saved sessions

Snapshots are copies. They may allocate outside realtime paths. A snapshot
should be clear about ownership and lifetime.

The UI should be able to render from a snapshot. Tests should be able to assert
against a snapshot. Debug tools should not inspect internal tables directly.

## Invariants

Add invariant checks early.

Examples:

- every node's rack exists
- every cable's source and destination ports exist
- every cable connects compatible port kinds and directions
- every port's node exists
- every param's node exists
- every plugin's node exists
- every plugin node maps to one plugin
- every `nodesByRack` row points to existing nodes owned by that rack
- every `portsByNode` row points to ports owned by that node
- every `paramsByNode` row points to params owned by that node
- every plugin UI references an existing plugin
- no destroyed ID remains in an index
- no process plan references a dead node, port, plugin, or param

Invariant checks do not need to run on every frame. They should run in tests,
diagnostics, after session load, and after complex graph edits.

## Hot Paths

Keep hot paths direct when the model adds no value.

Direct:

- JACK buffer pointer lookup inside the callback
- plugin process call once the process plan is compiled
- WGPU command submission from a prepared draw list
- pointer hit testing against a prepared target table

Operation path:

- node created or destroyed
- cable created or destroyed
- plugin loaded or unloaded
- parameter metadata changed
- plugin UI opened or closed
- session loaded
- audio backend reconfigured
- renderer surface recreated

Do not force everything through a message loop. The useful part is the split
between data, operations, systems, adapters, and snapshots.

## Boundary Rule

One model owns truth: `NilrackModel`.

External APIs get handles. Threads get snapshots or compiled plans. Tests get
snapshots. UI gets draw lists and input targets. The audio callback gets a
process plan. Nobody gets to improvise a second state model because it is
convenient in the moment.
