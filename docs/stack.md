# nilrack Stack

These are the dependency decisions for nilrack. Each entry explains what the
dependency does and why it was chosen.

## wayland-nim

Wayland client binding for Nim. Same package used by Triad:
`https://github.com/panno8M/wayland-nim`. Protocol stubs are generated per
protocol and live in `src/protocols/`. Wayland details stay in the platform
layer; the rest of the app sees normalized input events.

## wgpu-native

GPU renderer backend. C ABI. `NilDrawList` is the stable rendering model;
`wgpu-native` is a backend detail. The draw list API must not leak wgpu types.
A software debug backend stays possible by keeping draw commands renderer-agnostic.

## JACK

Audio I/O. JACK owns the realtime callback and works under PipeWire via
`pipewire-jack`. The JACK layer stays thin: register ports, translate buffers,
forward the process callback. Native PipeWire support comes later behind the
same backend interface.

## CLAP

Plugin format. Plain C ABI. The cleanest first implementation path. CLAP is
the reference format for the internal plugin model. LV2 and VST3 adapters
follow the same internal shape.

## LV2

Plugin format. Metadata lives in TTL files. A scanner can read LV2 descriptors
without loading native code, which makes out-of-process scanning lower risk for
LV2 than for other formats. Ports, params, and state map to the internal model
via the adapter.

## VST3

Plugin format. COM vtable interface. The binary layout is C-compatible: each
interface is a struct of function pointers under the hood. Nim binds it by
defining vtable structs against the SDK headers in
`/usr/src/vst3sdk/pluginterfaces/`. No C++ compiler needed.
`GetPluginFactory` is an `extern "C"` symbol. Data structs (`PFactoryInfo`,
`PClassInfo`, etc.) are plain POD. See [plugins.md](plugins.md) for the
adapter approach.

## wayembed

Owned project (`~/dev/wayembed`). Written in Zig. Embeds native Wayland plugin
UIs as `wl_subsurface`s. Exposes a C ABI in `include/wayembed.h`. nilrack
links it as an internal dependency — users do not install it separately.

The host implements `wayembed_host_interface`: a struct of function pointers
that provides upstream Wayland globals (`wl_compositor`, `wl_seat`, etc.) and
lifecycle callbacks (`on_client_connected`, `on_embed_mapped`, etc.).

## nimkdl

Owned project, available in nimble. KDL 2.0 parser and serializer for Nim.
Used for session files and plugin scan cache. API: `parseKdl(string) → KdlDoc`,
`encodeKdlDoc(obj) → KdlDoc`. See [session.md](session.md).

## stb_truetype

Single C header. Rasterizes a TTF font into a glyph atlas on startup. Text
runs in `NilDrawList` reference the atlas. No runtime dependency, no font
rendering framework.

## Janet

Embedded scripting language. Compiled in statically — no loadable modules.
Sandboxed: no networking, no process spawning, no arbitrary file I/O, fuel
limit to prevent runaway scripts. See [janet.md](janet.md) for the role Janet
plays and the integration pattern from Triad.
