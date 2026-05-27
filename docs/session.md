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

See [stack.md](stack.md) for the `nimkdl` dependency.

## Plugin Scan Cache

The out-of-process plugin scanner writes its results in the same KDL format.
Each cache entry records the plugin path, mtime at scan time, and the descriptor
data (name, version, ports, params, UI capabilities, scan status). nilrack
skips the scanner for any plugin whose path and mtime match the cache.

The scan cache is a separate file from the session. It persists across sessions.
See [plugins.md](plugins.md) for the scanning process.
