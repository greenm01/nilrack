# nilrack Audio

The audio engine owns the realtime graph. The JACK backend owns the realtime
callback. The two talk through a compiled `ProcessPlan` and preallocated queues.

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
- clear, copy, add, and process ops
- event queues
- parameter slots
- bypass and mute flags
- meter output slots

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
