# nilrack Build Phases

Each phase produces a working build that proves something real before the next
phase builds on it. The architecture docs behind each phase are linked where
relevant.

---

## Phase 0 — Foundation (done)

- [x] Architecture and design docs
- [x] Data-oriented design spec
- [x] Domain docs (ui, audio, plugins, session, janet, stack)
- [x] Source skeleton: types, state, entities, adapter stubs
- [x] `nimble build` compiles clean

---

## Phase 1 — Wayland Window, GPU Renderer, JACK Passthrough

Proves Wayland, GPU rendering, event dispatch, JACK, and the UI/audio thread
boundary. No plugins yet. See [architecture.md](architecture.md) milestone 1.

**Platform**
- [x] wayland-nim bindings: window, surface, input events, frame callbacks
- [x] `src/platform/wayland_app.nim`: XDG shell window, dispatch loop, SHM fallback buffer
- [x] `src/platform/input.nim`: pointer and keyboard events normalized to `Msg`
- [x] `src/types/ui_values.nim`: `Msg` as object variant with typed payload

**Renderer**
- [x] webgpu-nim dep + `-d:wayland` + `-d:wgvkWGSL` compile flags (`config.nims`)
- [x] `src/render/wgpu_backend.nim`: Wayland surface, adapter, device, swapchain, clear
- [x] `src/render/renderer.nim`: begin/end frame, submit draw list (stub — clear only)
- [x] `src/render/draw_list.nim`: `NilDrawList` append helpers
- [x] `src/types/render_values.nim`: opaque wgpu handles, `WgpuBackend`, `Renderer` types
- [x] Pixie + 0xProto glyph atlas build on startup, text run draw command

**Audio**
- [x] JACK C bindings: client, ports, activate/deactivate, process callback
- [x] `src/audio/jack_backend.nim`: register ports, translate buffers
- [x] `src/audio/process_callback.nim`: passthrough + peak meter publish
- [x] `src/audio/rt_queue.nim`: preallocated UI→audio command queue
- [x] `src/types/audio_values.nim`: `JackBackend`, `MeterSnapshot`, `RtQueue` types

**Main loop**
- [x] TEA update loop in `src/nilrack.nim`: collect `Msg`, dispatch, handle close/Escape
- [x] `src/systems/ui_layout.nim`: rack shell layout (node area, status strip, meter bars)
- [x] `src/systems/render_projection.nim`: model → `NilDrawList`
- [x] `src/systems/ui_hit_test.nim`: `inputTargetAt` hit testing (stub)

**Meters**
- [x] Lock-free meter snapshot path: audio thread writes, UI thread reads via `Atomic[float32]`
- [x] Meter draw commands in draw list (`layoutShell`)
- [x] Meter display visible through rect draw pipeline in renderer

**Exit**
- [x] Clean shutdown: deactivate JACK → shutdown renderer → close Wayland

---

## Phase 2 — First CLAP Plugin

Load one CLAP plugin by path. Prove the plugin model, generated controls,
parameter editing, and state persistence. See [architecture.md](architecture.md)
milestone 2 and [plugins.md](plugins.md).

Foundation contracts for this phase live in [plugin-runtime.md](plugin-runtime.md),
[plugin-lifecycle.md](plugin-lifecycle.md), [audio-routing.md](audio-routing.md),
[graph-compile.md](graph-compile.md), and [plugin-events.md](plugin-events.md).

- [x] CLAP C bindings: entry, host, factory, plugin instance, audio ports,
  params, state, process structs
- [x] `src/plugins/clap_host.nim`: load plugin by path, instantiate, query
  descriptor, ports, params, and state capability
- [x] `src/plugins/plugin_adapter.nim`: translate CLAP metadata into internal model
- [x] `src/plugins/clap_host.nim`: activate and process through one CLAP plugin
- [ ] `src/systems/plugin_lifecycle.nim`: load, activate, deactivate, unload
- [ ] `src/systems/graph_compile.nim`: compile rack graph to `ProcessPlan`
- [x] `src/systems/graph_process_plan.nim`: single-plugin JACK process plan
- [ ] `src/systems/graph_process_plan.nim`: build process plan from compiled graph
- [x] Plugin node in rack UI: title bar and port slots
- [ ] Plugin node in rack UI: bypass toggle
- [x] Generated parameter controls: display-only slider rows
- [ ] Generated parameter controls: editable knob and slider widgets
- [ ] `src/systems/param_mapping.nim`: normalized param value → draw + input target
- [ ] Parameter edit queue: UI → audio thread via `rt_queue`
- [ ] State save: plugin → `StateBlobRef` → KDL session file
- [ ] State restore: KDL session file → `StateBlobRef` → plugin

---

## Spike — nilamp VST3 Wayland UI

This pulls a narrow part of Phase 4 and Phase 6 forward. It proves nilamp's
VST3 editor can render inside nilrack through wayembed before nilrack has a
general plugin host.

- [x] Thin C++ VST3 UI shim: load nilamp, create editor view, expose C ABI to Nim
- [x] `src/plugins/vst3_host.nim`: optional dynlib wrapper for the shim
- [ ] `src/embed/wayembed_host.nim`: move wayembed lifecycle out of the shim
  after the proof works
- [x] Strict VST3 Wayland path: parent surface proxy plus plugin-created
  subsurface adoption
- [x] Live smoke: nilrack window opens and nilamp editor appears on Wayland

---

## Phase 3 — Plugin Scanner

Scan CLAP, LV2, and VST3 directories without risking the host process. Cache
results. Show available plugins in a browser. See [plugins.md](plugins.md).

- [ ] `--scan-plugin <path>` mode in `nilrack.nim`: load plugin, write KDL to
  stdout, exit
- [ ] `src/systems/plugin_scan.nim`: fork scanner helper, collect KDL output,
  handle non-zero exit as scan-failed
- [ ] Scan result schema in KDL: path, mtime, descriptor, ports, params,
  UI caps, scan status
- [ ] Disk cache: read/write scan cache via `nimkdl`, skip unchanged plugins
- [ ] Plugin browser UI: list scanned plugins, filter by format and name
- [ ] Drag plugin from browser to rack canvas → nodeCreate + pluginAttachToNode

---

## Phase 4 — LV2 and VST3

Three formats, one internal model. See [plugins.md](plugins.md) and
[architecture.md](architecture.md) milestone 3.

**LV2**
- [ ] LV2 C bindings: lilv or direct lv2 headers for TTL parsing
- [ ] `src/plugins/lv2_host.nim`: parse TTL, instantiate, activate, process,
  params, state extension
- [ ] LV2 → internal plugin model via adapter

**VST3**
- [ ] VST3 Nim vtable structs against `/usr/src/vst3sdk/pluginterfaces/`
- [ ] `src/plugins/vst3_host.nim`: load factory, instantiate, activate, process,
  params, state streams
- [ ] VST3 → internal plugin model via adapter

**Unified**
- [ ] All three formats produce identical internal model entries
- [ ] State save/restore works for LV2 and VST3
- [ ] Generated controls available for all loaded plugins

---

## Phase 5 — Session Save and Restore

Save the full rack state to KDL. Load it on startup. See
[session.md](session.md).

- [ ] `src/systems/session_io.nim`: serialize `NilrackModel` → KDL document
- [ ] Restore: parse KDL → rebuild model, reload plugins, restore params and
  state blobs
- [ ] Auto-save on clean exit
- [ ] Load session from path on startup (`--session <path>`)

---

## Phase 6 — Native Wayland Plugin UI Embedding

Embed native Wayland plugin editors. Keep generated controls as fallback. See
[plugins.md](plugins.md) and [architecture.md](architecture.md) milestone 4.

- [ ] wayembed C bindings: `wayembed_host_interface`, server create/dispatch,
  embed attach/resize
- [ ] `src/embed/wayembed_host.nim`: implement host interface callbacks,
  manage embed lifecycle
- [ ] Plugin UI open/close operations: `pluginUiCreate`, `pluginUiDestroy`
- [ ] Subsurface positioning: sync embed position with node location on canvas
- [ ] Input and focus routing: pointer, keyboard, resize events to embedded surface
- [ ] Fallback: show generated controls when embed fails or closes
- [ ] Audio keeps running through any embed failure

---

## Phase 7 — XWayland Plugin UI Bridge

Support legacy LV2 and VST3 plugin editors that only expose X11 handles. See
[plugins.md](plugins.md) and [architecture.md](architecture.md) milestone 5.

- [ ] `src/embed/xwayland_bridge.nim`: X11/XCB bindings, bridge lifecycle
- [ ] Isolate bridge behind a clear module boundary
- [ ] Route focus, pointer, keyboard, and resize without stalling the app
- [ ] Fallback to generated controls if bridge embed fails
- [ ] Native Wayland shell has no X11 dependency

---

## Phase 8 — Janet Scripting

Embed Janet for MIDI mapping, rack automation, hotkey bindings, and session
macros. See [janet.md](janet.md).

- [ ] `src/janet/binding.c`: Janet C FFI layer — statically compiled, sandboxed,
  fuel limit, no loadable modules
- [ ] `src/janet/binding.nim`: Nim wrapper for C layer
- [ ] `src/janet/runtime.nim`: script loading, eval, event dispatch
- [ ] Event registration: `nilrack/on` equivalent for rack events
- [ ] Command dispatch: Janet handlers issue `Msg` values into update loop
- [ ] Snapshot API: expose model state to scripts as Janet values
- [ ] MIDI/param mapping scripts
- [ ] Hotkey bindings
- [ ] Session macro scripts

---

## Phase 9 — IPC

External control via Unix socket. Enables CLI tools and external integrations.
See [architecture.md](architecture.md).

- [ ] Unix socket server in the main loop
- [ ] Command protocol: text or KDL-based, maps to `Msg` values
- [ ] `nilrack-ctl` CLI tool: send commands to a running nilrack session
- [ ] IPC event stream: clients can subscribe to rack events

---

## Phase 10 — Native PipeWire Backend

Replace pipewire-jack with a direct PipeWire backend. JACK remains available.
See [audio.md](audio.md) and [stack.md](stack.md).

- [ ] PipeWire C bindings
- [ ] `src/audio/pipewire_backend.nim` behind the same backend interface as JACK
- [ ] Backend selection at startup
- [ ] JACK and PipeWire coexist; neither is removed

---

## Deferred

Items worth doing eventually but not blocking any of the above phases.

- [ ] `nph --check` in CI
- [ ] Nim test suite (`nimble test`): model invariants, entity ops, query correctness
- [ ] Software renderer backend for headless testing
- [ ] Plugin UI window detach (float plugin editor outside the rack window)
- [ ] Multi-rack support (more than one `RackId` active)
- [ ] MIDI mapping persistence in session
- [ ] Remote control over network (IPC over TCP/TLS)
