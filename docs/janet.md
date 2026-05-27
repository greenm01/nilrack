# nilrack Janet Scripting

Janet is embedded from the start. A scripting layer added after the fact
requires retrofitting the event system, command API, and snapshot API. Those
need to be designed with scripting in mind from day one.

## Role

Janet handles policy and automation. It does not own the renderer, the audio
path, or the draw list.

What Janet does:

- **MIDI and parameter mapping** — map CC inputs to parameters with curves,
  scaling, and multi-target binds
- **Rack automation** — respond to events (plugin loaded, parameter changed,
  XRun, transport state change) and issue commands
- **Hotkey bindings** — map key combinations to rack commands
- **Session macros** — assemble rack configurations, load presets, automate
  repetitive setup

Janet mutates the model by dispatching `Msg` values into the update loop. It
uses the same command API as IPC and UI input. The draw list follows from model
state — Janet does not touch it directly.

## Event → Command Pattern

The pattern is the same as Triad. Nim fires events into the Janet runtime.
Scripts register handlers. Handlers read a snapshot and issue commands.

```janet
(nilrack/on :plugin-loaded
  (fn [ev]
    (let [plugin (ev :plugin)]
      (when (= (plugin :name) "MyReverb")
        (nilrack/command "set-param" (plugin :id) "mix" 0.3)))))
```

Events mirror the `Msg` type: plugin lifecycle, parameter changes, transport
state, XRuns, session load/save, UI state changes.

Handlers issue commands by name. Commands map to the same operations available
from the UI and IPC. There is no separate scripting API — scripts and the UI
speak the same command language.

## Sandboxing

Janet is compiled in statically. Module loading is disabled. The runtime
disables networking, process spawning, and arbitrary file I/O. A fuel limit
caps execution time per eval to prevent runaway scripts from stalling the UI
thread.

This follows the same approach as Triad's `src/janet/binding.c`. That file is
the reference implementation for the binding layer.

## Reference Implementation

Triad's Janet integration covers the same pattern nilrack needs:

- `src/janet/binding.c` — C FFI layer, sandboxing, built-in functions
- `src/janet/binding.nim` — Nim wrapper
- `src/janet/runtime.nim` — script loading, caching, event dispatch
- `src/janet/janet_script_runtime.nim` — integration with the main daemon loop
- `src/janet/snapshot_api.nim` — converts model state to Janet expressions
- `src/janet/layout_api.nim` — context generation (analog for nilrack: param
  and graph context)

See [ui.md](ui.md) for the `Msg` type and update loop. See
[stack.md](stack.md) for the Janet dependency entry.
