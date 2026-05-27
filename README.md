# nilrack

`nilrack` is a native Wayland plugin rack for live audio graphs.

The project starts with a narrow target: a GPU-rendered Nim application that
hosts CLAP plugins through JACK, exposes generated controls, saves rack state,
and embeds native Wayland plugin UIs through `wayembed`.

See [docs/architecture.md](docs/architecture.md) for the working design.
