<h1 align=center>vacuited cli</h1>

<div align=center>

![GitHub last commit](https://img.shields.io/github/last-commit/vacuited/cli?style=for-the-badge&labelColor=101418&color=9ccbfb)&nbsp;![GitHub repo size](https://img.shields.io/github/repo-size/vacuited/cli?style=for-the-badge&labelColor=101418&color=d3bfe6)&nbsp;![GitHub license](https://img.shields.io/github/license/vacuited/cli?style=for-the-badge&labelColor=101418&color=96f1f1)

backend utility and control script for [vacuited-shell](https://github.com/vacuited/shell).

</div>

## features

| feature | description | backend / tools |
| :--- | :--- | :--- |
| **material you color extraction** | generates dynamic gtk, qt, terminal, and browser schemes from wallpapers | `materialyoucolor-py` |
| **video wallpaper engine** | frame extraction and playback support for animated backgrounds | `ffmpeg`, `mpv` |
| **circle to search** | interactive screen region capture and instant web query | `slurp`, `grim`, browser |
| **screen capture & recording** | screenshot editing and high-fps screen recording | `grim`, `slurp`, `swappy`, `gpu-screen-recorder` |
| **shell control & ipc** | daemon lifecycle management and workspace/panel toggle triggers | `quickshell` ipc |
| **papirus folder tinting** | synchronizes papirus directory icons with active palette | `caelestia-icons-sync.sh`, `papirus-folders` |
| **hardware telemetry & control** | platform profiles, fan curves, refresh rate, and turbo boost | `hp-wmi`, `intel_pstate`, `hyprctl` |

## usage

```fish
caelestia -h
```

### subcommands

| subcommand | description | key flags / args |
| :--- | :--- | :--- |
| `shell` | start, stop, reload, or inspect quickshell daemon | `-d`, `-r`, `-k` |
| `toggle` | toggle special workspaces and side panels | `<panel>` |
| `scheme` | generate and apply dynamic color schemes | `-w <image>`, `-s <style>` |
| `search` | search using an interactive screen region selection | |
| `screenshot` | capture screen with edit, copy, or save actions | `-m <mode>` |
| `record` | record screen with configurable fps and audio | `-f <fps>`, `-s` |
| `clipboard` | open clipboard history picker | |
| `emoji` | launch emoji and glyph picker | |
| `wallpaper` | apply static or video wallpapers with palette extraction | `<path>` |
| `resizer` | run window resizer daemon | |
| `hardware` | inspect telemetry and switch profiles, fans, and refresh rate | `status`, `profile`, `fans`, `rate`, `boost` |

## configuration

all settings live in `~/.config/caelestia/cli.json`.

## credits

| project | upstream / source | contribution |
| :--- | :--- | :--- |
| **caelestia-cli** | [caelestia-dots/cli](https://github.com/caelestia-dots/cli) | original backend utility and subcommands |
| **gpu-screen-recorder** | [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder) | low-overhead hardware screen capture |
| **papirus icon theme** | [PapirusDevelopmentTeam/papirus-icon-theme](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) | folder icon bases and folder recoloring scripts |
