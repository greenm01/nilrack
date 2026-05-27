# nilrack Architecture

`nilrack` is a native Wayland plugin rack for live audio graphs. It is not a
DAW. It has no timeline, no clip launcher, and no piano roll at the start. The
first job is simpler and harder: load plugins, connect them, process audio with
low latency, render a good rack UI, and survive live use.

The project favors small owned boundaries over a large framework. Nim owns the
application. C ABIs connect the pieces that need to speak to Linux audio,
Wayland, plugins, and GPU rendering.

## Goals

- Run as a native Wayland application.
- Render the application UI on the GPU.
- Host CLAP plugins first.
- Use JACK first, with a path to native PipeWire later.
- Embed native Wayland plugin UIs through `wayembed`.
- Keep the realtime audio path allocation-free after startup.
- Keep renderer, audio backend, plugin API, and UI embedding swappable.
- Save and restore rack/session state.

## Non-Goals

- Rebuild Element or JUCE.
- Build a full DAW.
- Host every plugin format in the first version.
- Support X11 plugin UIs in the first version.
- Let UI code or garbage collection enter the audio callback.
- Bind every function in a dependency before the host needs it.

## Stack

The first implementation uses Nim for the host and application code. Nim talks
directly to C-shaped libraries:

- Wayland client APIs for windows, surfaces, input, and frame timing.
- `wgpu-native` for GPU rendering.
- JACK for audio I/O.
- CLAP for plugin hosting.
- `wayembed` for native Wayland plugin UI embedding.

The audio engine may begin in Nim. That is acceptable if the realtime subset is
strict. The callback uses preallocated memory, plain objects, raw pointers,
fixed buffers, and no locks. If the Nim path fights us, the realtime core can
move behind the same internal API later.

## Process Model

`nilrack` starts as one process.

The UI thread owns Wayland dispatch, input routing, layout, renderer submission,
plugin scanning, session I/O, and user commands. The audio thread is owned by
JACK. It pulls immutable graph snapshots and consumes realtime-safe command
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

The UI layer owns the rack editor, plugin browser, generated parameter panels,
transport/status views, meters, and dialogs. It emits a draw list. It does not
call `wgpu-native` directly.

The first UI model should be immediate enough to move quickly, but not sloppy.
Widgets read application state, write commands, and emit draw operations. Long
lived state lives in the session model, not in renderer objects.

### Renderer

The renderer consumes a `NilDrawList`. `wgpu-native` is the first backend, not
the application rendering model.

The renderer interface should start small:

- begin frame
- resize
- upload or update texture
- submit draw list
- end frame
- shutdown

The first draw commands are enough to build the host UI:

- filled rectangle
- rounded rectangle
- border
- line and polyline
- text run
- image
- clip push/pop

Later commands can add curves, gradients, waveform batches, scope batches, and
instanced graph elements.

A software or shared-memory debug backend is worth keeping. It gives us a way
to test input, layout, and draw-list generation when GPU presentation is the
suspect.

### Audio Engine

The audio engine owns the realtime graph. It knows about nodes, ports, buffers,
MIDI/events, automation, and process order.

At startup or graph edit time, it allocates:

- audio buffers
- event buffers
- plugin process structures
- graph nodes and edges
- command queues
- meter snapshots

At callback time, it:

- reads the current graph snapshot
- drains realtime-safe control events
- processes nodes in order
- writes output buffers
- publishes meters through a lock-free snapshot path

The callback must not allocate, block, log, scan plugins, load files, create UI
objects, or call Nim code that can allocate.

### JACK Backend

JACK is the first audio backend because it gives us a clear realtime callback
and works well under PipeWire through pipewire-jack.

The JACK layer should stay thin:

- register ports
- activate/deactivate client
- translate JACK buffers into engine buffers
- forward process callbacks
- handle sample-rate and buffer-size changes

Native PipeWire can come later behind the same backend interface.

### Plugin Host

CLAP is the first plugin API. The CLAP host layer owns discovery, loading,
lifecycle, activation, process calls, parameters, events, state, and extension
lookup.

The first milestone loads one plugin. The second milestone scans a directory.
The third persists plugin state in a rack file.

LV2 and VST3 are later decisions. They should not shape the first engine.

### Plugin UI Embedding

`wayembed` is the native Wayland embedding layer. `nilrack` should link it as an
internal dependency, not require users to install a `wayembed` runtime library.

For v1, plugin UI policy is strict:

- native Wayland plugin UIs are supported through `wayembed`
- generated parameter UIs are always available
- X11 plugin UIs are not a v1 target
- plugin UI failure must not stop audio processing

### Session Model

The session model stores the rack graph, plugin references, parameter values,
connections, MIDI mappings, UI layout, and plugin state blobs.

The file format should be boring and inspectable. KDL is a good candidate
because the existing ecosystem already uses it. Binary blobs can be external
files or encoded fields after the basic model works.

## Threading Rules

The realtime thread is hostile territory.

Allowed:

- fixed-size arrays
- raw pointers
- preallocated ring buffers
- plain arithmetic
- CLAP process calls
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

The third build should prove the reason this project exists:

1. Embed a native Wayland plugin UI with `wayembed`.
2. Keep generated controls available as a fallback.
3. Route input and focus correctly.
4. Keep audio running when the embedded UI fails or closes.

## Open Questions

- Which Nim Wayland binding should own the first platform layer, or should the
  first pass bind only the calls we need?
- Should KDL be the rack file format from day one?
- Should plugin scanning run in-process or in a helper process?
- How much of `wgpu-native` should be wrapped before we write the draw-list
  backend?
- When native PipeWire arrives, does it replace JACK or sit beside it?

## Design Principle

Own the host model. Borrow the plumbing.

The stable parts of `nilrack` should be its rack graph, realtime rules, draw
list, session model, and plugin-host policy. Dependencies can change. The
project should not become a thin skin over any one toolkit, renderer, plugin
SDK, or audio server.
