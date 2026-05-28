# nilrack Architecture

`nilrack` is a native Wayland plugin rack for live audio graphs. It is not a
DAW. It has no timeline, no clip launcher, and no piano roll at the start. The
first job is simpler and harder: load plugins, connect them, process audio with
low latency, render a good rack UI, and survive live use.

The project favors small owned boundaries over a large framework. Nim owns the
application. C ABIs connect the pieces that need to speak to Linux audio,
Wayland, plugins, and GPU rendering.

Domain docs:
[dod.md](dod.md) —
[ui.md](ui.md) —
[audio.md](audio.md) —
[audio-routing.md](audio-routing.md) —
[plugins.md](plugins.md) —
[plugin-runtime.md](plugin-runtime.md) —
[plugin-lifecycle.md](plugin-lifecycle.md) —
[graph-compile.md](graph-compile.md) —
[plugin-events.md](plugin-events.md) —
[session.md](session.md) —
[janet.md](janet.md) —
[stack.md](stack.md)

## Goals

- Run as a native Wayland application.
- Render the application UI on the GPU.
- Host CLAP, LV2, and VST3 plugins in v1.
- Use JACK first, with a path to native PipeWire later.
- Embed native Wayland plugin UIs through `wayembed`.
- Support XWayland plugin UIs through an isolated bridge.
- Keep the realtime audio path allocation-free after startup.
- Keep renderer, audio backend, plugin API, and UI embedding swappable.
- Save and restore rack/session state.

## Stack

Nim owns the host and application code. Dependency decisions and rationale are
in [stack.md](stack.md).

## Process Model

`nilrack` starts as one process.

The UI thread owns Wayland dispatch, input routing, layout, renderer submission,
session I/O, and user commands. Plugin scanning runs in a helper process —
crashes during scan must not affect a running session. The audio thread is owned
by JACK. It pulls immutable graph snapshots and consumes realtime-safe command
queues.

The audio callback never calls UI code. It never logs. It never allocates. It
never waits on a mutex. If a task cannot obey those rules, it belongs on the UI
or worker side.

## Major Modules

### App Shell

The app shell owns process startup, configuration, dependency initialization,
and shutdown order. It wires the subsystems together but does not contain graph,
plugin, or rendering policy.

### Wayland Platform

The platform layer creates the main window, receives input, tracks scale and
output changes, and exposes native handles needed by the renderer and
`wayembed`.

The rest of the app sees normalized events:

- pointer motion
- button press/release
- scroll
- key press/release
- text input
- focus changes
- resize
- frame callbacks

Wayland details stay here unless a subsystem needs a raw handle.

### UI and Layout

The UI follows TEA: the view function is a pure transform from `NilrackModel`
to `NilDrawList + InputTargetList`. Input events become typed `Msg` values and
enter the update loop. There is no widget framework. See [ui.md](ui.md).

### Renderer

The renderer consumes a `NilDrawList`. `webgpu-nim` with WGVK is the first
backend, not the application rendering model. A software debug backend stays
possible by keeping draw commands renderer-agnostic. See [ui.md](ui.md) for
the draw command set.

### Audio Engine

The audio engine owns the realtime graph. At callback time it reads a compiled
`ProcessPlan` and preallocated queues. It never allocates, logs, or touches
application state. Routing is patchbay-first in the model and compiled into
fixed realtime work. See [audio.md](audio.md) and
[audio-routing.md](audio-routing.md). The exact model-to-plan contract is in
[graph-compile.md](graph-compile.md).

### JACK Backend

JACK owns the realtime callback and works under PipeWire via `pipewire-jack`.
The JACK layer stays thin. Native PipeWire support comes later behind the same
backend interface. See [audio.md](audio.md).

### Plugin Host

v1 hosts CLAP, LV2, and VST3 as adapters into one internal plugin model. The
rack graph does not know which format produced a node. Plugin scanning runs
out-of-process. The realtime boundary uses opaque plugin runtime refs and a
small ops table, following Carla's proven host division while keeping nilrack's
data-oriented model. See [plugins.md](plugins.md) and
[plugin-runtime.md](plugin-runtime.md). Plugin lifetime and realtime event
flow are covered by [plugin-lifecycle.md](plugin-lifecycle.md) and
[plugin-events.md](plugin-events.md).

### Plugin UI Embedding

Native Wayland plugin UIs embed through `wayembed`. XWayland plugin UIs go
through an isolated bridge. Generated parameter controls are always available.
Plugin UI failure must not stop audio processing. See [plugins.md](plugins.md).

### Session Model

The session stores the rack graph, plugin references, parameter values,
connections, MIDI mappings, UI layout, and plugin state blobs. The file format
is KDL via `nimkdl`. See [session.md](session.md).

### Janet Scripting

Janet is embedded from the start. It handles MIDI and parameter mapping, rack
automation, hotkey bindings, and session macros. It dispatches `Msg` values
into the update loop — the same command API used by IPC and the UI. See
[janet.md](janet.md).

## Threading Rules

The realtime thread is hostile territory.

Allowed:

- fixed-size arrays
- raw pointers
- preallocated ring buffers
- plain arithmetic
- CLAP, LV2, VST3 process calls via compiled plan
- atomic reads/writes with a clear ownership model

Forbidden:

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

Commands from UI to audio cross a preallocated queue. Audio-to-UI state crosses
through snapshots: meters, transport state, XRuns, plugin errors, and graph
health.

## First Milestone

The first useful build should do this:

1. Open a native Wayland window.
2. Initialize the wgpu renderer.
3. Draw the rack shell, a node area, and a status strip.
4. Start a JACK client.
5. Pass audio input to output.
6. Show realtime meters in the UI.
7. Exit cleanly.

That milestone proves Wayland, GPU rendering, event dispatch, JACK, and the
thread boundary before plugin hosting enters the picture.

## Second Milestone

The second build should load one CLAP plugin by path:

1. Load and instantiate the plugin.
2. Activate it at the JACK sample rate and buffer size.
3. Process audio through it.
4. Render generated controls for its parameters.
5. Send parameter edits from UI to audio safely.
6. Save and restore the plugin state.

## Third Milestone

The third build expands plugin coverage:

1. Load one LV2 plugin by path or URI.
2. Load one VST3 plugin by path.
3. Map CLAP, LV2, and VST3 parameters into the same internal model.
4. Save and restore state for all three formats.
5. Keep generated controls available for every loaded plugin.

## Fourth Milestone

The fourth build should prove the reason this project exists:

1. Embed a native Wayland plugin UI with `wayembed`.
2. Keep generated controls available as a fallback.
3. Route input and focus correctly.
4. Keep audio running when the embedded UI fails or closes.

## Fifth Milestone

The fifth build makes legacy plugin editors usable:

1. Show an XWayland LV2 or VST3 plugin editor.
2. Keep the bridge isolated from the native Wayland shell.
3. Route focus, pointer, keyboard, and resize events without stalling the app.
4. Fall back to generated controls if the editor cannot embed cleanly.

## Design Principle

Own the host model. Borrow the plumbing.

The stable parts of `nilrack` should be its rack graph, realtime rules, draw
list, session model, and plugin-host policy. Dependencies can change. The
project should not become a thin skin over any one toolkit, renderer, plugin
SDK, or audio server.
