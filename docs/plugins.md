# nilrack Plugin Host

CLAP, LV2, and VST3 are adapters into one internal plugin model. The rack
graph does not know which format produced a node. Format-specific logic stays
in adapter modules.

See [dod.md](dod.md) for how plugins map to the data model. See
[stack.md](stack.md) for the per-format dependency decisions. Thread and
process ownership is summarized in [threads.md](threads.md).

## Internal Plugin Model

Each adapter translates format-specific data into:

- descriptor and metadata
- audio and event ports
- parameters
- activation and deactivation
- process callback
- state save and restore
- UI capability record
- error record

The rack graph processes nodes through one internal plugin instance interface.
Format tags (`PluginApi` enum) live in the plugin record — they do not leak
into the graph, engine, or UI.

At runtime, the internal interface is a small ops table plus an opaque runtime
pointer. `ProcessPlan` stores those runtime refs. Format adapters translate
generic process and parameter calls into CLAP, LV2, or VST3 calls. See
[plugin-runtime.md](plugin-runtime.md). Live runtime ownership and destruction
rules are in [plugin-lifecycle.md](plugin-lifecycle.md). Realtime parameter,
MIDI, transport, and feedback records are in [plugin-events.md](plugin-events.md).

## CLAP

Plain C ABI. The cleanest first implementation path. CLAP's host model is
modern and the API is well-specified. Host CLAP first; LV2 and VST3 follow the
same internal shape.

## LV2

Metadata lives in TTL files alongside the plugin binary. A scanner can read
descriptors, ports, and parameter definitions without loading native code. This
makes LV2 the lowest-risk format to scan. State persistence uses the LV2 State
extension. Ports and params map directly to the internal model.

## VST3

COM vtable interface. The binary layout is C-compatible: each interface is a
struct of function pointers. Nim binds VST3 by defining vtable structs against
the SDK headers in `/usr/src/vst3sdk/pluginterfaces/`. No C++ compiler needed.

Entry point: `GetPluginFactory` is an `extern "C"` symbol. Data structs
(`PFactoryInfo`, `PClassInfo`, etc.) are plain POD. Parameter staging, state
serialization, and the process loop follow the patterns in
`nilamp/native/src/nilamp_vst3.mm`.

## Out-of-Process Scanning

Plugin scanning runs in a helper process. A plugin that crashes or corrupts
memory during scan must not affect a running nilrack session.

```text
nilrack forks nilrack-scan --scan-plugin <path>
    |
    | helper loads plugin enough to inspect it
    | extracts descriptor, ports, params, UI caps
    | writes KDL to stdout
    | exits
    |
nilrack reads KDL result
    |
    +-- success → add to plugin catalog
    +-- non-zero exit or empty output → record as scan-failed
```

The scanner extracts descriptors and capabilities only. It must not activate a
plugin, call process, run audio, open a native editor, or persist plugin state.
Runtime behavior belongs to the main host lifecycle after the user loads a
plugin.

Scan results cache to disk in KDL format (via `nimkdl`), keyed by plugin path
and mtime. nilrack only re-runs the helper when a plugin's mtime changes.
See [session.md](session.md) for the cache format and atomic write pattern.

The helper has a hard timeout named by a configurable constant in code. On
timeout, nilrack kills the helper and records `ScanFailed{reason: Timeout}`.
Non-zero exit, empty output, and malformed KDL also record typed failure
reasons. Automatic catalog loading skips a path and mtime that match a failed
scan entry until the file changes or the user explicitly requests a rescan.

UI capability is scan metadata. The descriptor records whether generated UI,
native Wayland, XWayland bridge, or no native UI is available. Loaded plugin
records may copy the needed capability fields, but the scanner is the source for
catalog capability data.

The helper is the same nilrack binary invoked with a scan flag. It links
against CLAP, LV2, and VST3 adapter code. A plugin that overflows a buffer
kills the helper, not nilrack.

## UI Embedding

### Native Wayland (wayembed)

`wayembed` handles native Wayland plugin UIs. nilrack links it as an internal
dependency. The host implements `wayembed_host_interface`, providing upstream
Wayland globals and lifecycle callbacks. When a plugin opens a native Wayland
surface, `wayembed` creates a `wl_subsurface` parented to the rack window.

### XWayland Bridge

XWayland plugin UIs go through an isolated bridge. The bridge makes existing
LV2 and VST3 plugin editors usable when they only expose X11 handles. It lives
behind a clear boundary. The native Wayland shell does not depend on X11 for
its own windowing, input, or rendering.

Bridge lifecycle:

1. UI thread requests a native editor.
2. nilrack starts one bridge process for that plugin UI.
3. UI sends position, resize, focus, and input over a bounded pipe protocol.
4. Bridge reports ready, closed, failed, or timed out.
5. On bridge exit, timeout, malformed reply, or plugin editor close, nilrack
   destroys the embed record and falls back to generated controls.

The bridge never processes audio and never mutates `NilrackModel` directly.

### Generated Parameter UI

Generated parameter controls are always available when a plugin has parameters.
They do not require a native editor to open or succeed. Plugin UI failure must
not stop audio processing — nilrack falls back to generated controls and keeps
running.
