<h1 align=center>Vacuited CLI</h1>

<div align=center>

![GitHub last commit](https://img.shields.io/github/last-commit/vacuited/cli?style=for-the-badge&labelColor=101418&color=9ccbfb)&nbsp;![GitHub repo size](https://img.shields.io/github/repo-size/vacuited/cli?style=for-the-badge&labelColor=101418&color=d3bfe6)&nbsp;![GitHub license](https://img.shields.io/github/license/vacuited/cli?style=for-the-badge&labelColor=101418&color=96f1f1)

Backend utility and control script for [vacuited-shell](https://github.com/vacuited/shell).

</div>

## Features

| Feature | Description | Backend & Tools |
| :--- | :--- | :--- |
| **Material You Color Extraction** | Generates dynamic GTK, Qt, terminal, and browser schemes from active wallpapers | `materialyoucolor-py` |
| **Video Wallpaper Engine** | Frame extraction and playback control for animated background loops | `ffmpeg`, `mpv` |
| **Circle to Search** | Interactive screen region selection with instant web search queries | `slurp`, `grim`, browser |
| **Screen Capture & Recording** | Screenshot region capture, swappy annotations, and high-FPS video recording | `grim`, `slurp`, `swappy`, `gpu-screen-recorder` |
| **Shell Control & IPC** | Daemon lifecycle management and workspace/panel toggle triggers | `quickshell` IPC |
| **Papirus Folder Tinting** | Synchronizes Papirus directory icons with active palette | `caelestia-icons-sync.sh`, `papirus-folders` |
| **HP Victus Hardware Control** | Platform profiles (`quiet`, `cool`, `balanced`, `performance`), fan curves, refresh rate, and Intel Turbo Boost | `hp-wmi`, `intel_pstate`, `hyprctl` |

<details><summary id="dependencies">External Dependencies</summary>

- [`libnotify`](https://gitlab.gnome.org/GNOME/libnotify) — desktop notifications
- [`swappy`](https://github.com/jtheoof/swappy) — interactive screenshot editor
- [`grim`](https://gitlab.freedesktop.org/emersion/grim) — Wayland screenshot capture
- [`slurp`](https://github.com/emersion/slurp) — Wayland interactive region selection
- [`wl-clipboard`](https://github.com/bugaevc/wl-clipboard) — clipboard read/write
- [`gpu-screen-recorder`](https://git.dec05eba.com/gpu-screen-recorder/about) — hardware-accelerated screen recorder
- [`ffmpeg`](https://ffmpeg.org/) — video frame extraction
- [`papirus-folders`](https://github.com/PapirusDevelopmentTeam/papirus-folders) — Papirus folder tinting
- [`materialyoucolor-py`](https://github.com/Tuhin-th/materialyoucolor-py) — Material You M3 palette extraction
- [`cliphist`](https://github.com/sentriz/cliphist) — clipboard history manager
- [`fuzzel`](https://codeberg.org/dnkl/fuzzel) — application and clipboard picker

</details>

## Installation

### User Environment Installation

Build the Python wheel and install into `~/.local`:

```bash
# Clean previous builds
rm -rf dist/*.whl

# Build wheel package
python -m build --wheel

# Install into ~/.local
python -m installer --overwrite-existing --prefix ~/.local dist/*.whl
```

### Shell Completions

For Fish shell:
```fish
cp completions/caelestia.fish ~/.config/fish/completions/caelestia.fish
```

For Bash or system-wide installation:
```bash
sudo cp completions/caelestia.fish /usr/share/fish/vendor_completions.d/caelestia.fish
```

## Permissions & Hardware Setup

### Hardware Control Helper
Hardware profile transitions (including switching out of HP Victus proprietary `cool` profile) execute via `/usr/local/bin/caelestia-hardware-helper` backed by a Polkit rule to permit zero-password execution.

### Automatic Folder Tinting
To allow automatic Papirus folder recoloring without entering a password:

```bash
echo "$USER ALL=(ALL) NOPASSWD: $(which papirus-folders)" | sudo tee /etc/sudoers.d/papirus-folders
sudo chmod 440 /etc/sudoers.d/papirus-folders
```

## Subcommands Reference

Explore all subcommands via `caelestia -h`.

| Subcommand | Description | Primary Options / Flags |
| :--- | :--- | :--- |
| `shell` | Start, stop, reload, or send messages to the Quickshell daemon | `-d` (detach), `-r` (restart), `-k` (kill) |
| `toggle` | Toggle special workspaces and shell drawers | `<panel>` (`sidebar`, `dashboard`, `utilities`) |
| `scheme` | Generate and apply dynamic color schemes | `-w <image>`, `-s <style>` |
| `search` | Capture an interactive screen region and search online | |
| `screenshot` | Capture screen with edit, copy, or save actions | `-m <mode>` (`region`, `screen`), `-e`, `-c`, `-s` |
| `record` | Record screen with configurable FPS and audio | `-f <fps>`, `-s` (stop) |
| `clipboard` | Open clipboard history selection menu | |
| `emoji` | Launch emoji and glyph picker | |
| `wallpaper` | Apply static or animated wallpapers with palette extraction | `<path>`, `-r` (random) |
| `resizer` | Run window resizer daemon | |
| `hardware` | Inspect telemetry and switch profiles, fan curves, and refresh rates | `status`, `profile`, `fans`, `rate`, `boost` |

## User Templates

Custom theme templates can be placed in `~/.config/caelestia/templates/`.

### Syntax

`{{ <color>.<format> }}`

- `<color>` is a theme color role derived from Material You (e.g. `primary`, `secondary`, `surface`, `background`).
- `<format>` is the output format: `hex`, `rgb`, `hsl`, or single channels (`red`, `green`, `blue`, `hue`, `saturation`, `lightness`).

Output theme files are written to `~/.local/state/caelestia/theme/`.

## Configuration

All CLI settings reside in `~/.config/caelestia/cli.json`.

<details><summary>Example cli.json configuration</summary>

```json
{
    "screenshot": {
        "app": "swappy",
        "action": "edit",
        "regionAction": "edit",
        "fullscreenAction": "notify",
        "copyOnSave": true
    },
    "record": {
        "refreshRate": 144,
        "extraArgs": []
    },
    "theme": {
        "enableTerm": true,
        "enableHypr": true,
        "enableGtk": true,
        "enableQt": true,
        "iconThemeDark": "Papirus-Dark",
        "iconThemeLight": "Papirus-Light"
    },
    "wallpaper": {
        "postHook": ""
    }
}
```

</details>

## Credits

| Project | Upstream / Source | Contribution |
| :--- | :--- | :--- |
| **caelestia-cli** | [caelestia-dots/cli](https://github.com/caelestia-dots/cli) | Original backend utility, IPC commands, and scheme engine |
| **gpu-screen-recorder** | [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder) | High-performance hardware video capture |
| **Papirus Icon Theme** | [PapirusDevelopmentTeam/papirus-icon-theme](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) | Folder icons and recoloring automation scripts |
