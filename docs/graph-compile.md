# nilrack Graph Compile

`graph_compile` is the only system that turns `NilrackModel` routing into
realtime audio work. It reads racks, nodes, ports, cables, plugins, params, and
runtime refs. It writes a `ProcessPlan`.

The callback executes the plan. It does not interpret cables.

## Inputs

The compiler reads model truth:

```text
RackData
NodeData
PortData
CableData
PluginData
ParamData
```

It also reads runtime availability from the plugin runtime store. A plugin node
without a live runtime can still exist in the model, but it cannot compile to a
plugin process op.

Host input and output are normal nodes:

- `nkInput` provides host audio and MIDI inputs.
- `nkOutput` receives host audio and MIDI outputs.
- Plugin nodes use `PluginRuntimeRef` entries from the runtime store.

## Compile Steps

The compiler should follow a fixed order:

1. Collect nodes, ports, cables, and plugin runtime refs for one rack.
2. Validate cable endpoints, port direction, port kind, and channel policy.
3. Reject feedback cycles for v1.
4. Expand bus-level cables into channel edges.
5. Sort nodes into process order.
6. Assign buffer slots for host I/O, plugin I/O, mixes, and scratch space.
7. Emit fixed ops: clear, copy, add, process, MIDI merge, bypass, mute, meter.
8. Return a complete plan or a compile error snapshot.

Partial plans should not be published. If compile fails, keep the previous plan
running and report the compile error to the UI.

## Channel Expansion

The user model stores bus cables:

```text
CableData(srcPort: stereo out, dstPort: stereo in)
```

The compiler expands that cable:

```text
src channel 0 -> dst channel 0
src channel 1 -> dst channel 1
```

V1 channel rules:

- mono output to wider input duplicates mono;
- equal channel counts map one-to-one;
- wider output to mono input rejects unless an explicit mapping exists;
- other mismatches reject until advanced mapping exists.

The plan stores channel edges and ops. It does not store the original cable as
runtime routing work.

## ProcessPlan Shape

The final realtime shape should use bounded arrays, not heap-owned `seq`
storage. Exact limits can grow, but the callback needs fixed iteration bounds.

Conceptually, `ProcessPlan` contains:

```text
generation
rackId
sampleRate
blockSize
nodeCount
nodes[]
bufferCount
buffers[]
opCount
ops[]
runtimeCount
runtimes[]
eventQueues
meterSlots
diagnosticFlags
```

Ops are small records:

```text
clear buffer
copy source buffer -> destination buffer
add source buffer -> destination buffer
merge MIDI source -> destination
process plugin runtime
bypass node
mute node
publish meter
```

The callback walks `ops[]` in order. All pointer and buffer decisions are made
before publication.

## Bypass And Mute

Host bypass and plugin bypass are different.

- `NodeData.bypassed`: host behavior. The compiler emits pass-through work
  when I/O is compatible, otherwise silence.
- `NodeData.muted`: host behavior. The compiler emits silence for that node's
  outputs.
- Plugin bypass params: plugin-owned params. They are routed through normal
  parameter events.

For v1, bypass should process no plugin code when pass-through or silence is
enough. Later modes can add tail-preserving bypass as a node policy.

## MIDI

MIDI routing follows the same model as audio:

- MIDI ports are bus-level `PortData`.
- Cables connect MIDI outputs to MIDI inputs.
- Compile emits bounded MIDI event-buffer routes.
- Multiple MIDI sources merge by sample offset.
- Overflow sets a plan or snapshot flag; the callback does not log.

The event representation is defined in [plugin-events.md](plugin-events.md).

## Compile Errors

Compile errors are data, not callback behavior:

- missing port;
- direction mismatch;
- kind mismatch;
- unsupported channel mismatch;
- missing plugin runtime;
- feedback cycle;
- plan capacity exceeded.

The UI can render these errors against nodes and cables. The audio callback
keeps running the last valid plan until a replacement is published.

## Carla Prior Art

Carla's `PatchbayGraph` records explicit node and port connections, then lets
its graph code build a rendering sequence. nilrack should copy that separation:
model cables are edit/session data; process ops are compiled callback data.
