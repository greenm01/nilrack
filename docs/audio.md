# nilrack Audio

The audio engine owns the realtime graph. The JACK backend owns the realtime
callback. The two talk through a compiled `ProcessPlan` and preallocated queues.
Thread ownership is summarized in [threads.md](threads.md).

## Audio Engine

The engine knows about nodes, ports, buffers, MIDI events, and process order.

At startup or graph edit time, it allocates:

- audio buffers
- event buffers
- plugin process structures
- compiled graph nodes and channel edges
- command queues
- meter snapshots

At callback time, it:

- reads the current graph snapshot
- drains realtime-safe control events
- processes nodes in order
- writes output buffers
- publishes meters through a lock-free snapshot path

The callback must not allocate, block, log, scan plugins, load files, create UI
objects, or call Nim code that may allocate.

## JACK Backend

JACK is the first audio backend. It provides a clear realtime callback and
works under PipeWire via `pipewire-jack`. The JACK layer stays thin:

- register ports
- activate and deactivate the client
- translate JACK buffers into engine buffers
- forward process callbacks
- handle sample-rate and buffer-size changes

Native PipeWire support comes later behind the same backend interface.
See [stack.md](stack.md).

## ProcessPlan

The realtime thread never touches `NilrackModel` directly. It reads a compiled
`ProcessPlan`.

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

`ProcessPlan` contains only what the callback needs:

- ordered node list
- plugin runtime refs
- port buffer bindings
- clear, copy, add, future delay, and process ops
- event queues
- event target lookup tables
- parameter slots
- bypass and mute flags
- reported plugin latency
- meter output slots
- diagnostics slots

The plan is compiled on the UI thread whenever the graph changes. A new plan
atomically replaces the old one. The callback always reads the current plan.
Plugin runtime refs point to a format-neutral ops table. The callback drains
generic parameter edits and lets the adapter map them to CLAP, LV2, or VST3.
Bus-level cables are expanded to channel-level routing during graph compile.

See [audio-routing.md](audio-routing.md), [graph-compile.md](graph-compile.md),
[plugin-events.md](plugin-events.md), [dod.md](dod.md), and
[plugin-runtime.md](plugin-runtime.md) for the full realtime model.

## Audio-to-UI State

The audio thread never writes to application state. It publishes through
lock-free snapshot slots:

- per-node meter levels
- XRun count
- transport state
- plugin process errors
- graph health flags

The UI thread reads snapshots each frame and emits `Msg` values for anything
that changed.

## Diagnostics

The audio callback reports health through one fixed diagnostics record:

```text
AudioCallbackDiagnostics
  generation: atomic uint32
  counters: array[AudioDiagnosticKind, atomic uint32]

AudioDiagnosticKind
  QueueFull
  EventBufferFull
  MidiBufferFull
  FeedbackDropped
  StaleEvent
  XRun
  PluginProcessError
  TopologyRefreshRequested
  RetireQueueOverflow
  ReconfigRequested
```

The callback may only increment counters and bump `generation`. It does not
write strings or detailed error payloads. The UI thread reads diagnostics
through a snapshot helper and turns counter changes into `Msg` values, logs, or
visible warnings.

## Reconfiguration

Sample-rate and buffer-size changes are backend reconfiguration events. The
realtime side does only bounded work:

1. JACK or the audio backend reports a new sample rate or buffer size.
2. The realtime path sets `ReconfigRequested` and outputs silence if the current
   plan no longer matches the backend block shape.
3. The UI thread observes the flag, publishes a safe replacement or empty plan,
   and retires the old plan with the normal epoch mechanism.
4. The UI thread deactivates affected plugin runtimes, reactivates them with the
   new sample rate or block size, recompiles, and publishes a matching plan.
5. Normal processing resumes after the replacement plan is visible.

The callback must not allocate buffers, activate plugins, or recompile the graph
while handling reconfiguration.

## Realtime Rules

The realtime thread is hostile territory. These rules are not negotiable.

**Allowed:**

- fixed-size arrays
- raw pointers
- preallocated ring buffers
- plain arithmetic
- plugin process calls (CLAP, LV2, VST3 via compiled plan)
- atomic reads and writes with a clear ownership model

**Forbidden:**

- heap allocation
- string construction
- logging
- locks
- file I/O
- plugin scanning
- UI calls
- blocking syscalls
- exceptions
- unbounded loops over user-controlled data

Commands from the UI to audio cross a preallocated queue. If a task cannot
obey these rules, it belongs on the UI or worker thread.
