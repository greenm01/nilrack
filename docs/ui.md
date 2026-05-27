# nilrack UI

The UI stack has no widget framework. Everything renders through `NilDrawList`.
Input flows through a hit target table and enters the main loop as typed messages.

## Main Loop (TEA)

The main loop follows The Elm Architecture:

- **Model** — `NilrackModel`. The single source of truth. See [dod.md](dod.md).
- **Msg** — typed union of all events: Wayland input, IPC commands, audio thread
  snapshots, Janet messages, plugin events, scan results.
- **Update** — routes each `Msg` to the right operation module. Returns an effect
  queue for deferred work (graph recompile, plugin load, renderer upload).
- **View** — pure function from `NilrackModel` to `NilDrawList + InputTargetList`.

```text
collect events
    |
    v
update(model, msg) → effect queue
    |
    v
drain effects
    |
    v
view(model) → draw list + input targets
    |
    v
submit to renderer
```

Janet dispatches `Msg` values into the update loop. IPC does the same over a
Unix socket. The command API is the `Msg` type — there is no separate scripting
API. See [janet.md](janet.md).

## Draw List

`NilDrawList` is the stable rendering model. The UI layer never calls
`wgpu-native` directly. Draw commands are flat, batchable records. The first
set covers the full host UI:

- filled rect, rounded rect, border
- line, polyline, bezier
- text run
- image
- clip push/pop
- meter batch

Later commands can add waveform batches, scope batches, and instanced graph
elements.

A software debug backend stays possible. It lets you test layout and input
dispatch without GPU presentation. See [dod.md](dod.md) for the render model.

## Rack Graph Editor

The primary surface. A 2D canvas with pan and zoom. Plugin nodes sit at
arbitrary positions. Cables are cubic bezier curves from output port slots to
input port slots. Signal type (audio, MIDI, CV) drives cable color. Signal
level can drive cable alpha or thickness.

Key interactions:

- pan and zoom the canvas
- drag nodes to reposition
- drag from a port to connect a cable
- click a cable to select or delete it
- box-select multiple nodes

Hit testing uses the input target table. Each port slot, node title bar, and
cable segment registers an `InputTargetId` during the view pass.
`inputTargetAt(x, y)` maps a pointer position to a logical target, which
becomes a `Msg`.

## Widget Layer

No widget framework. `src/ui/widgets.nim` contains draw functions that emit
draw commands and push input targets. Widget state lives in `NilrackModel`,
not in widget objects.

First-pass widget set:

- knob (rotary, with arc indicator)
- slider (horizontal and vertical)
- button (momentary and toggle)
- label and value readout
- dropdown

Parameter panels for plugins use these widgets. The generated parameter UI is
always available when a plugin has parameters, regardless of whether a native
plugin editor is open.

## Font Rendering

`stb_truetype` rasterizes a TTF font into a glyph atlas on startup. Text run
commands in `NilDrawList` reference glyph positions in the atlas. One C header,
no runtime dependency. See [stack.md](stack.md).

## Input Dispatch

The view pass produces `NilDrawList` and `InputTargetList` together.
`InputTargetList` is a flat array of screen-space regions, each bound to a
logical `InputTargetId`. On pointer events, `inputTargetAt(x, y)` returns the
target. The target resolves to a `Msg`. The `Msg` enters `update`.

Keyboard events route through the focus model. The focused `InputTargetId`
receives key messages. Janet-registered hotkeys intercept before focus routing.

## Visual References

- **Element** — graph editor feel, clean node canvas
- **Gig Performer** — live performance focus, direct and fast to navigate
- **Carla** — functional completeness, patchbay UX (not the Qt visual style)

nilrack is fully custom-rendered. None of these tools' frameworks are used.
The goal is their intent: a fast, purpose-built live audio UI.
