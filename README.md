<h1 align=center>Vacuited CLI</h1>

<div align=center>

![GitHub last commit](https://img.shields.io/github/last-commit/vacuited/cli?style=for-the-badge&labelColor=101418&color=9ccbfb)&nbsp;![GitHub repo size](https://img.shields.io/github/repo-size/vacuited/cli?style=for-the-badge&labelColor=101418&color=d3bfe6)&nbsp;![GitHub license](https://img.shields.io/github/license/vacuited/cli?style=for-the-badge&labelColor=101418&color=96f1f1)

Backend utility and control script for [vacuited-shell](https://github.com/vacuited/shell).

</div>

## Features

| Feature | Description | Backend / Tools |
| :--- | :--- | :--- |
| **Material You color extraction** | Generates dynamic GTK, Qt, terminal, and browser schemes from wallpapers | `materialyoucolor-py` |
| **Video wallpaper engine** | Frame extraction and playback support for animated backgrounds | `ffmpeg`, `mpv` |
| **Circle to search** | Interactive screen region capture and instant web query | `slurp`, `grim`, browser |
| **Screen capture & recording** | Screenshot editing and high-FPS screen recording | `grim`, `slurp`, `swappy`, `gpu-screen-recorder` |
| **Shell control & IPC** | Daemon lifecycle management and workspace/panel toggle triggers | `quickshell` IPC |
| **Papirus folder tinting** | Synchronizes Papirus directory icons with active palette | `caelestia-icons-sync.sh`, `papirus-folders` |
| **Hardware telemetry & control** | Platform profiles, fan curves, refresh rate, and turbo boost | `hp-wmi`, `intel_pstate`, `hyprctl` |

## Usage

```fish
caelestia -h
```

### Subcommands

| Subcommand | Description | Key Flags / Args |
| :--- | :--- | :--- |
| `shell` | Start, stop, reload, or inspect Quickshell daemon | `-d`, `-r`, `-k` |
| `toggle` | Toggle special workspaces and side panels | `<panel>` |
| `scheme` | Generate and apply dynamic color schemes | `-w <image>`, `-s <style>` |
| `search` | Search using an interactive screen region selection | |
| `screenshot` | Capture screen with edit, copy, or save actions | `-m <mode>` |
| `record` | Record screen with configurable FPS and audio | `-f <fps>`, `-s` |
| `clipboard` | Open clipboard history picker | |
| `emoji` | Launch emoji and glyph picker | |
| `wallpaper` | Apply static or video wallpapers with palette extraction | `<path>` |
| `resizer` | Run window resizer daemon | |
| `hardware` | Inspect telemetry and switch profiles, fans, and refresh rate | `status`, `profile`, `fans`, `rate`, `boost` |

## Configuration

All settings live in `~/.config/caelestia/cli.json`.

## Credits

| Project | Upstream / Source | Contribution |
| :--- | :--- | :--- |
| **caelestia-cli** | [caelestia-dots/cli](https://github.com/caelestia-dots/cli) | Original backend utility and subcommands |
| **gpu-screen-recorder** | [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder) | Low-overhead hardware screen capture |
| **Papirus Icon Theme** | [PapirusDevelopmentTeam/papirus-icon-theme](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) | Folder icon bases and folder recoloring scripts |
