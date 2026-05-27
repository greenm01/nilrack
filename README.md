# nilrack

`nilrack` is a native Wayland plugin rack for live audio graphs.

The project starts with a practical target: a GPU-rendered Nim application that
hosts CLAP, LV2, and VST3 plugins through JACK, exposes generated controls,
saves rack state, embeds native Wayland plugin UIs through `wayembed`, and
supports XWayland plugin UIs through an isolated bridge.

See [docs/architecture.md](docs/architecture.md) and
[docs/dod.md](docs/dod.md) for the working design.

Project docs follow [docs/dreyer-style.md](docs/dreyer-style.md).
