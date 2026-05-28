# nilrack Threads And Processes

This is the ownership map for nilrack runtime work. Domain docs can add detail,
but thread and process boundaries should point back here.

## Inventory

| Boundary | Owner | Lifetime | Allowed ops | Forbidden ops | Inbound | Outbound |
| --- | --- | --- | --- | --- | --- | --- |
| UI thread | app shell | process lifetime | Wayland dispatch, `Msg` update, model operations, layout, renderer submit, plan publication, job dispatch | realtime plugin processing, blocking plugin scans, direct callback storage mutation | Wayland events, audio snapshots, worker results, scanner results, bridge events | effects, plan publish, worker jobs, scanner jobs, bridge commands |
| JACK realtime callback | JACK backend | JACK activation | read current `ProcessPlan`, drain plan queues, call plugin process ops, write meters and diagnostics | allocation, locks, logging, file I/O, model access, plugin load/unload, UI calls, fd polling | published plan pointer, preallocated queues, JACK buffers | meter snapshots, diagnostics counters, callback epoch |
| Plugin scanner helper process | plugin scan system | one plugin scan | load enough plugin code to inspect descriptors, write KDL, exit | activate, process audio, open native editor, mutate session | scan request path | KDL on stdout, exit status |
| State-save worker | session system | job lifetime or worker lifetime | call adapter save/load state, write sidecars, report result | audio callback work, direct model mutation, unsafe plugin kill in-process | state save/restore job | result record, timeout or failure code |
| Janet runtime | UI thread guest | app lifetime | handle events within fuel budget, read snapshots, dispatch `Msg` commands | direct model access, audio calls, blocking I/O, process spawning | nilrack events, snapshot values | committed `Msg` commands |
| XWayland bridge process | embed system | per plugin UI | host X11 editor window, forward input/resize/focus, report close/failure | audio processing, model mutation, plugin DSP calls | UI open/resize/focus/input commands | bridge status, editor close/failure |
| Future plugin bridge process | plugin runtime system | per bridged runtime or group | own external plugin instance, process shared audio/event buffers, return status | direct `NilrackModel` access, UI rendering ownership | shared buffers, lifecycle pipe messages | process status, state blobs, diagnostics |
| Future plugin-event thread | plugin runtime system | app or runtime lifetime | poll plugin fds and timers, translate adapter callbacks to effects | audio processing, direct model mutation | fd/timer registrations, adapter events | bounded records to UI thread |

## Handoff Rules

- `NilrackModel` belongs to the UI thread.
- The audio callback reads `ProcessPlan`, preallocated queues, and JACK buffers
  only.
- Worker, scanner, bridge, and Janet results return as data records. The UI
  thread applies model changes through operations.
- Realtime-to-UI data is snapshots and atomic diagnostics, never strings or heap
  objects allocated by the callback.
- UI-to-realtime data is plan publication or bounded queues owned by the plan.
- Plugin scanner and bridge processes may be killed on timeout. In-process
  plugin calls cannot be safely killed; timeout marks the runtime or job failed
  and quarantined.

See [audio.md](audio.md), [plugin-lifecycle.md](plugin-lifecycle.md),
[plugin-runtime.md](plugin-runtime.md), [session.md](session.md),
[plugins.md](plugins.md), [ui.md](ui.md), and [janet.md](janet.md) for the
subsystem contracts.
