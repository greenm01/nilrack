# nilrack Plugin Events

Plugin events are nilrack-owned records that cross realtime boundaries. CLAP,
LV2, and VST3 event structs stay inside adapters.

The goal is one event vocabulary for generated controls, MIDI routing,
automation, transport, scripting, and plugin feedback.

## Event Types

The first event set should cover:

```text
PluginParamGestureBegin
PluginParamValue
PluginParamGestureEnd
PluginMidiEvent
PluginTransportSnapshot
PluginFeedback
```

Parameter events carry nilrack IDs:

```text
PluginParamValue
  pluginId
  paramId
  value
  valueKind
  sampleOffset
```

`valueKind` is either normalized or plain. The UI can work in normalized values
while adapters receive the plain values they need. The adapter owns conversion
to CLAP, LV2, or VST3 process input.

Gesture events bracket user edits:

```text
PluginParamGestureBegin(pluginId, paramId)
PluginParamGestureEnd(pluginId, paramId)
```

V1 generated sliders may send only value edits, but the record shape should
leave room for gestures before automation and host recording arrive.

## MIDI Events

MIDI events carry sample offsets and raw short-message or byte payload data:

```text
PluginMidiEvent
  portId
  sampleOffset
  size
  bytes
```

The queue capacity is fixed. If an event does not fit, the producer sets an
overflow flag. The callback does not allocate a larger event buffer.

## Transport Snapshot

Transport is a snapshot, not a stream of commands:

```text
PluginTransportSnapshot
  playing
  frame
  bpm
  beatPosition
  timeSigNumerator
  timeSigDenominator
```

Fields can be added when transport becomes real. Until then, adapters should
receive an empty or stopped transport state.

## Queues

UI-to-audio events use preallocated queues. Typical producers:

- generated controls;
- keyboard or MIDI mapping;
- Janet;
- IPC;
- session restore.

Audio-to-UI plugin feedback uses snapshots or bounded queues. Typical payloads:

- plugin-updated parameter value;
- gesture begin or end from plugin UI;
- process error flag;
- event queue overflow flag;
- requested restart or process callback.

The audio callback may set flags and write fixed records. It must not allocate,
format strings, or log.

## Adapter Translation

Each plugin adapter maps nilrack events to native events:

- CLAP maps param values and gestures to CLAP event lists.
- LV2 maps params to control ports or atom events.
- VST3 maps params to process parameter queues.
- MIDI maps to each format's supported event input.

The graph compiler and UI never construct native plugin events. They only
construct nilrack events.

## Ordering

Within one block:

- events are ordered by `sampleOffset`;
- equal offsets keep producer order where practical;
- parameter gestures surround value edits from the same source;
- MIDI merge preserves sample offset ordering.

Ordering work happens before or during queue drain into preallocated buffers.
No unbounded sort runs in the callback.

## Overflow

Overflow is expected under stress and must be visible:

```text
queueFull
eventBufferFull
midiBufferFull
feedbackDropped
```

Overflow policy is conservative: drop the newest event, set a flag, and keep
audio running. Later policies can be per-event-type, but the callback still
must not allocate.

## State Restore

Session restore may enqueue parameter values after plugin state load if the
session stores both a state blob and visible param values. State blobs are
adapter-owned. Parameter events are host-owned. The restore system decides the
order outside the callback.
