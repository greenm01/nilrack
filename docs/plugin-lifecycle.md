# nilrack Plugin Lifecycle

Plugin lifecycle is the ownership contract between `NilrackModel`, live plugin
runtimes, and the audio callback. The model owns plugin truth. Runtime storage
owns live handles. The audio callback reads only a published `ProcessPlan`.

This contract matters because plugin unload is dangerous in a realtime host. A
plan can contain pointers to plugin runtimes. A runtime must not be destroyed
while any callback could still read a plan that references it.

## State Flow

Plugin state moves through these stages:

```text
discovered
loaded
instantiated
activated
processing
stopped
retired
destroyed
```

- **Discovered**: scanner or direct path produced a descriptor.
- **Loaded**: the plugin library or bundle is open.
- **Instantiated**: the plugin object exists and metadata has been queried.
- **Activated**: the plugin has sample rate and block-size context.
- **Processing**: the plugin is ready for calls from `ProcessPlan`.
- **Stopped**: processing has ended but the instance can still hold state.
- **Retired**: no new plan may reference the runtime.
- **Destroyed**: native instance, library handle, and adapter storage are gone.

`NilrackModel` does not store the live state machine. It stores durable plugin
identity, params, ports, UI state, and state blobs. Runtime state lives in a
plugin runtime store outside the model.

## Plan Publication

The UI thread builds new plans. The audio callback executes the current plan.

```text
UI thread
  load or edit model
  update runtime store
  compile ProcessPlan
  publish plan pointer
  enqueue old plan for retirement

audio callback
  read current plan pointer once
  execute plan
  publish callback epoch
```

Plan publication must be pointer-sized and non-blocking for the callback. The
callback must not allocate, lock, or inspect `NilrackModel` while switching
plans.

## Deferred Retirement

Old plans and plugin runtimes retire after publication. Retirement has two
steps:

1. Publish a replacement plan that no longer references the old runtime.
2. Destroy the old plan and runtime only after the audio callback cannot still
   be using the previous plan.

The exact mechanism can be an epoch counter, a small retire queue drained from
the UI thread, or another wait-free scheme. The rule is fixed: destruction is
never immediate when a runtime may have been visible to the callback.

```text
old plan references plugin A
        |
        v
publish new plan without plugin A
        |
        v
retire old plan and plugin A after callback epoch advances
```

For v1, stopping JACK before process exit is enough for final shutdown. Live
plugin removal, graph rebuilds, and session reload need deferred retirement.

## Thread Ownership

The UI thread may:

- load plugin libraries;
- instantiate plugins;
- query descriptors, params, ports, and state support;
- activate and deactivate plugins outside callback time;
- compile and publish process plans;
- retire old plans and runtimes after the callback is clear.

The audio callback may:

- read the current plan;
- drain realtime-safe queues referenced by that plan;
- call plugin process functions through `PluginRuntimeOps`;
- write snapshots and overflow flags.

The audio callback must not:

- open or close plugin libraries;
- destroy plugin instances;
- allocate or free runtime storage;
- call model operations;
- log plugin errors directly.

## Load And Restore

Session restore should use this order:

1. Rebuild model records for racks, nodes, ports, params, and cables.
2. Load and instantiate plugin runtimes.
3. Apply plugin state blobs while the runtime is stopped.
4. Activate runtimes for the current sample rate and block size.
5. Compile and publish the first plan.
6. Start audio processing.

If state restore fails, the runtime should report an adapter error and keep the
model load failure visible to the UI. The callback should not participate in
state restore.

## Error Handling

Plugin lifecycle errors cross as data:

- load failed;
- instantiate failed;
- activate failed;
- process failed;
- state save failed;
- state restore failed;
- retire queue overflowed.

Errors belong in snapshots or diagnostics queues. The callback only marks
flags. UI, logging, and user-facing text happen off the realtime thread.

## Carla Prior Art

Carla keeps plugin instances behind engine graph structures and coordinates
graph changes before processing. nilrack should keep the same ownership
division, but avoid callback locks as the main safety device. Published plans
and deferred retirement fit nilrack's data-oriented model better.
