# nilrack Session

The session model stores everything needed to restore a rack: graph topology,
plugin references, parameter values, connections, MIDI mappings, UI layout, and
plugin state blobs.

## What Gets Saved

- rack graph structure (nodes, cables, port connections)
- plugin references (path for CLAP/VST3, URI for LV2)
- parameter values for every loaded plugin
- MIDI and control mappings
- UI layout (node positions, panel sizes, scroll state)
- plugin state blobs (opaque binary data from each plugin's save call)

## File Format

KDL via `nimkdl`. KDL is text, human-readable, and inspectable with a text
editor. The format is boring by design. If something goes wrong with a session
file, a user can open it and understand what they are looking at.

Plugin state blobs are binary. They encode as base64 fields in the KDL document
or as external sidecar files referenced by name. Sidecar files keep the main
session file readable when state blobs are large.

Default policy: inline blobs smaller than 4 KiB; store larger blobs as sidecar
files referenced from KDL. A future zipped session bundle can keep the same
logical references while packaging sidecars with the main document.

See [stack.md](stack.md) for the `nimkdl` dependency.

## Plugin State

Plugin state save and restore are non-realtime operations. The audio callback
never reads or writes `StateBlobRef`.

Save flow:

1. The UI thread asks the adapter to save plugin state.
2. The adapter returns an opaque blob or an error.
3. The session system stores a small inline blob or writes a sidecar file.
4. `NilrackModel` records the resulting `StateBlobRef`.

If a native plugin UI changes hidden plugin state, the adapter marks state
dirty through feedback. The UI thread pulls a fresh state blob later. The
callback only sets a fixed flag.

Restore flow:

1. Instantiate the runtime while stopped.
2. Load the opaque plugin blob through the adapter.
3. Apply explicit nilrack parameter values for tracked params.
4. Activate the runtime and compile a plan.

The blob comes first because it may restore hidden format state. Explicit
nilrack param records come after it because they are the visible session truth
for tracked params.

If loading a state blob changes ports, params, buses, or latency, the adapter
reports a topology-change request. The UI thread re-queries the runtime, updates
`NilrackModel`, recompiles the graph, and publishes a matching plan before the
runtime processes audio.

## Plugin Scan Cache

The out-of-process plugin scanner writes its results in the same KDL format.
Each cache entry records the plugin path, mtime at scan time, and the descriptor
data (name, version, ports, params, UI capabilities, scan status). nilrack
skips the scanner for any plugin whose path and mtime match the cache.

Failed scans are cache entries too. A `ScanFailed` record stores path, mtime,
exit status, and a short error code. nilrack must not auto-load a plugin whose
current path and mtime match a failed scan entry. A user-triggered rescan may
clear or replace the failed entry.

The scan cache is a separate file from the session. It persists across sessions.
See [plugins.md](plugins.md) for the scanning process.
