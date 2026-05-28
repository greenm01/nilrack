# nilrack Session

The session model stores everything needed to restore a rack: graph topology,
plugin references, parameter values, connections, MIDI mappings, UI layout, and
plugin state blobs.

Thread ownership for session jobs is summarized in [threads.md](threads.md).

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

All persistent files use the same write pattern:

```text
write temp file
fsync temp file
rename over target
fsync containing directory where available
```

Sidecars are written and synced before the main KDL. On session save, nilrack
computes the referenced sidecar set and removes unreferenced sidecars in the
session directory.

See [stack.md](stack.md) for the `nimkdl` dependency.

## Plugin State

Plugin state save and restore are non-realtime operations. The audio callback
never reads or writes `StateBlobRef`.

Save flow:

1. The UI thread schedules a state-save job.
2. The adapter returns an opaque blob or an error.
3. The session system stores a small inline blob or writes a sidecar file.
4. `NilrackModel` records the resulting `StateBlobRef`.

State save runs off the realtime thread. It should also run off the UI thread
when the adapter call may block. In-process v1 cannot safely kill a hung plugin
state call. A timeout marks the job `SaveTimeout`, quarantines that runtime for
future user action, and keeps the UI responsive; a future out-of-process bridge
can terminate its helper process.

If a native plugin UI changes hidden plugin state, the adapter marks state
dirty through feedback. The UI thread pulls a fresh state blob later. The
callback only sets a fixed flag.

Restore order is defined in [plugin-lifecycle.md](plugin-lifecycle.md). The
short rule is: load opaque plugin state first, re-query any topology changed by
that state, then apply explicit nilrack parameter values for tracked params.

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
