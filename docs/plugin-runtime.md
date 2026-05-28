# nilrack Plugin Runtime

The plugin runtime is the boundary between nilrack's rack model and external
plugin APIs. The graph, UI, session, and audio plan use nilrack records and
IDs. CLAP, LV2, and VST3 details stay inside format adapters.

Carla proves the useful host shape: one shared plugin boundary, with each
format translating behind it. nilrack keeps that boundary, but adapts it to
the data-oriented model in [dod.md](dod.md). There is no plugin object tree.
The realtime path reads compiled records and calls function pointers.

## Runtime Boundary

`NilrackModel` owns plugin metadata, params, ports, node relationships, and
state refs. `ProcessPlan` is a callback-safe snapshot built from that model.
Loaded plugin instances sit behind opaque runtime pointers.

```text
PluginEventContext
  paramValues: ptr UncheckedArray[PluginParamValue]
  paramValueCount: uint32
  midiEvents: ptr UncheckedArray[PluginMidiEvent]
  midiEventCount: uint32
  transport: ptr PluginTransportSnapshot

PluginAudioBus
  portId: PortId
  channels: ptr UncheckedArray[pointer]
  channelCount: uint32

ProcessContext
  frames: uint32
  audioInputs: ptr UncheckedArray[PluginAudioBus]
  audioInputBusCount: uint32
  audioOutputs: ptr UncheckedArray[PluginAudioBus]
  audioOutputBusCount: uint32
  events: PluginEventContext

PluginRuntimeOps
  activate
  deactivate
  process
  saveState
  loadState
  destroy

PluginRuntimeRef
  runtime: pointer
  ops: ptr PluginRuntimeOps
```

The exact Nim names can change, but the shape should not. The process plan
stores runtime refs, bus layouts, event slices, and buffer bindings. It does
not store CLAP, LV2, or VST3 event structs as shared data.

Runtime lifetime is covered by [plugin-lifecycle.md](plugin-lifecycle.md).
The model-to-plan compile contract is covered by
[graph-compile.md](graph-compile.md). The event vocabulary is covered by
[plugin-events.md](plugin-events.md).

```mermaid
flowchart TD
  UI[UI / Generated Controls]
  Model[NilrackModel<br/>PluginData, ParamData, PortData]
  Queue[RT Queue<br/>Plugin events]
  Plan[Compiled ProcessPlan]
  Audio[JACK Audio Callback]

  Ops[PluginRuntimeOps<br/>format-neutral function table]
  Ref[PluginRuntimeRef<br/>ops + opaque runtime pointer]

  Clap[CLAP Adapter<br/>clap_host.nim]
  Lv2[LV2 Adapter<br/>future lv2_host.nim]
  Vst3[VST3 Adapter<br/>future vst3_host.nim]

  ClapWire[CLAP events / process structs]
  Lv2Wire[LV2 control ports / atom events]
  Vst3Wire[VST3 ProcessData / param queues]

  UI -->|drag slider| Model
  UI -->|enqueue param edit| Queue

  Model -->|graph compile| Plan
  Plan --> Ref
  Ref --> Ops

  Audio -->|read immutable plan| Plan
  Audio -->|drain edits| Queue
  Audio -->|process(ProcessContext)| Ops

  Ops --> Clap
  Ops --> Lv2
  Ops --> Vst3

  Clap --> ClapWire
  Lv2 --> Lv2Wire
  Vst3 --> Vst3Wire
```

## Parameter Edits

Generated controls emit format-neutral parameter events:

```text
PluginParamValue
  pluginId
  paramId
  value
  valueKind
  sampleOffset
```

The UI updates `ParamData.currentVal` through normal model operations and
pushes the edit into a preallocated queue. The audio callback drains that queue
and constructs `ProcessContext` slices for each plugin.

Adapters map generic event slices to native process input:

- CLAP writes preallocated `clap_event_param_value` records.
- LV2 writes control ports or preallocated atom-event buffers.
- VST3 writes preallocated process parameter queues.

Do not introduce a shared CLAP-like event record. That would make LV2 and VST3
fit CLAP instead of fitting nilrack.

## Carla Prior Art and the Data-Oriented Shift

Carla's useful lesson is the host boundary. Its engine speaks to a common
plugin base type. CLAP, LV2, and VST3 implementations translate inside their
own subclasses. For example, Carla uses a separate RT call `setParameterValueRT`
that subclasses handle before the `process` call.

While Carla's approach works for an OOP design, its separated RT parameter
calls are not the shape nilrack should expose as the shared runtime boundary.
CLAP, LV2, and VST3 each still need native process data with the right lifetime
during `process`.

nilrack diverges from Carla's separated event calls to prioritize a
zero-allocation data flow. Instead of multiple functions, nilrack uses a unified
`process` call taking a `ProcessContext`. The context is a per-process view
into plan-owned audio buses and preallocated event slices. The adapter
translates those slices into its own preallocated native scratch, such as CLAP
event lists or VST3 `ProcessData`, during the process call. That keeps the
callback allocation-free without pretending native plugin APIs need no scratch
storage.

In nilrack:

- shared state lives in passive records and dense tables;
- relationship truth is carried by typed IDs;
- hot audio data and event slices cross via `ProcessContext`;
- plugin behavior crosses through a small ops table;
- format adapters own native handles, API calls, and preallocated native scratch.

## Ownership Rules

- `NilrackModel` is the source of truth for plugin metadata and session state.
- `ProcessPlan` is the audio-thread snapshot.
- Format adapters own external plugin instances and native event buffers.
- UI, graph, session, and audio scheduling code do not switch on plugin format.
- Plugin API tags select an adapter at load or scan time, not during graph
  processing.

This keeps CLAP, LV2, and VST3 dry without hiding their real differences.
