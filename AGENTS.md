# AGENTS.md - guide for AI coding agents

This file documents project conventions, build mechanics, and design rules for
agents working on `nilrack`. Humans should read `README.md` first. This file
adds the operational details an agent needs to act safely.

## Working Rules

1. Think before coding. State assumptions, surface tradeoffs, and ask when
   intent is genuinely ambiguous.
2. Keep changes simple. Do not add speculative features, abstractions, or
   configurability.
3. Make surgical edits. Touch only files needed for the request and clean up
   only the mess your change creates.
4. Define verification. Turn every bugfix or feature into concrete checks and
   run them before finishing when feasible.
5. Format Nim-family files with `nph`. Run `nph` on touched `.nim`,
   `.nims`, and `.nimble` files before verification, and use `nph --check`
   when validating formatting without writing changes.
6. Do not run Nim tests or builds in parallel. `nimble test*`,
   `nimble build*`, direct `nim c`, and related commands can share build
   outputs and corrupt or link against stale artifacts when run concurrently.
   Run these verification and build commands serially.
7. Before committing code, run a targeted compile or check. Until the project
   has a fuller build, use `nim c src/nilrack.nim`.
8. Keep docs crisp. Follow `nilrack/docs/dreyer-style.md` for project
   documentation.
9. Keep runtime code data-oriented. Follow `docs/dod.md` when adding state,
   graph, plugin, renderer, audio, UI, or session code.
10. Keep files small and focused. Split by domain when a file starts mixing
    storage, policy, adapter code, and rendering concerns.

## Documentation Style

`nilrack/docs/dreyer-style.md` is the document style guide for nilrack.

Write like an engineer with a point of view. Avoid corporate filler. Prefer
short, active sentences. Use lists for specs, not as a substitute for thought.

When editing docs, scan for banned language:

```text
robust
seamless
leveraging
In order to
The fact that
It is important to note that
dynamic
canonical
```

Use the project name `nilrack` in lowercase unless it starts a sentence.

## Data-Oriented Runtime Direction

The runtime model is the source of truth. Do not rebuild a plugin-host-shaped
object graph on the side.

When changing runtime, state, graph, plugin, renderer, UI, or session code:

1. Define passive records in `src/types`.
2. Store long-lived entities in dense tables under the model.
3. Use typed logical IDs. ID `0` is null.
4. Maintain relationship indexes in operation modules, not in systems or
   adapters.
5. Read through queries and iterators.
6. Mutate through entity operations.
7. Cross thread or API boundaries with snapshots, compiled plans, or draw
   lists.

The audio callback never owns application state. It reads a compiled
`ProcessPlan` and realtime-safe queues. It does not allocate, log, lock, scan
plugins, load files, or call UI code.

The renderer consumes a draw list. WGPU is a backend, not the UI model. Keep a
software/debug backend possible by keeping the draw command API independent of
WGPU.

## Plugin Host Direction

v1 targets CLAP, LV2, and VST3. Treat them as adapters into one internal plugin
model:

- descriptors
- ports
- params
- state blobs
- process calls
- UI capability records
- errors

The rack graph should not care which plugin API produced a node. Format-specific
logic belongs in adapter modules.

Generated parameter UI must remain available. Native Wayland plugin UI goes
through `wayembed`. XWayland plugin UI goes through an isolated bridge.

## Verification

For documentation-only changes:

```sh
rg -n --glob '!docs/dreyer-style.md' "robust|seamless|leverag|In order to|The fact that|It is important to note that|dynamic|canonical" docs README.md
```

For current code changes:

```sh
nim c src/nilrack.nim
```

Clean generated local binaries before committing:

```sh
rm -f src/nilrack
```

If new tests, build steps, or live harnesses are added later, update this file
with the exact commands.

## Boundaries

One model owns truth: `NilrackModel`.

External APIs get handles. Threads get snapshots or compiled plans. Tests get
snapshots. UI gets draw lists and input targets. The audio callback gets a
process plan. Do not invent a second state model because it is convenient for a
single feature.
