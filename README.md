the control script and backend utility for [vacuited-shell](https://github.com/vacuited/shell)

## features

- **material you color extraction**: generates dynamic gtk, qt, terminal, and browser color schemes from wallpapers.
- **video wallpaper support**: high-performance video wallpaper playback and frame extraction via `ffmpeg`.
- **circle to search**: screen region search command (`caelestia search`).
- **screen tools**: customizable screenshots (`grim` / `slurp` / `swappy`) and screen recording with custom fps (`gpu-screen-recorder`).
- **shell control**: daemon management and ipc triggers for workspaces, sidebars, and panels (`caelestia toggle`, `caelestia shell`).
- **papirus folder color sync**: automatic folder icon tinting via `papirus-folders`.
- **hardware control & telemetry**: full cli backend for hp victus hardware control (`caelestia hardware`), supporting platform profiles (`quiet`, `cool`, `balanced`, `performance`), fan boost (`auto`, `max`), display refresh rate (`60`, `144`), intel turbo boost (`on`, `off`), and json telemetry.

## usage

```sh
caelestia -h
```

### subcommands

- `shell`: start, restart, or message the quickshell daemon
- `toggle`: toggle special workspaces and panels
- `scheme`: generate and apply color schemes
- `search`: search using an interactive screen region
- `screenshot`: capture screen with edit, copy, or save actions
- `record`: screen recording daemon with configurable frame rates
- `clipboard`: open clipboard history
- `emoji`: emoji and glyph picker
- `wallpaper`: set static or video wallpapers with palette extraction
- `resizer`: window resizer daemon
- `hardware`: inspect telemetry or control platform profiles, fans, refresh rate, and turbo boost

## configuration

all settings live in `~/.config/caelestia/cli.json`.
