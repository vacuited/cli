#!/usr/bin/env bash
# install.sh — Build and install the vacuited CLI (`caelestia`)
#
# What it does:
#   1. Checks dependencies (auto-installs missing ones on Arch-based distros)
#   2. Compiles/verifies syntax and builds a wheel in a temporary directory
#   3. Installs to $PREFIX (default ~/.local, no sudo for the CLI itself)
#   4. Installs & validates fish completions and configures PATH safely
#   5. Cleans outdated dist-info / orphaned site-packages and verifies the result

set -Eeuo pipefail

if [ -t 1 ]; then
    C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'; C_R=$'\033[1;31m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
else
    C_G=''; C_Y=''; C_R=''; C_B=''; C_0=''
fi
log()  { printf '%s[+]%s %s\n' "$C_G" "$C_0" "$*"; }
info() { printf '%s[*]%s %s\n' "$C_B" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
err()  { printf '%s[-]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit 1; }

CLEANUP_PATHS=()
cleanup() {
    local p
    for p in "${CLEANUP_PATHS[@]+"${CLEANUP_PATHS[@]}"}"; do
        [ -n "$p" ] && rm -rf "$p" 2>/dev/null || true
    done
}
trap cleanup EXIT

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
[ -n "$SCRIPT_PATH" ] && [ -e "$SCRIPT_PATH" ] || die "Do not pipe this script into bash. Clone the repo and run ./install.sh."
SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH" 2>/dev/null || printf '%s' "$SCRIPT_PATH")"
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd -P)"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PREFIX="${HOME}/.local"
PYTHON_BIN=""
MIN_PY_MAJOR=3
MIN_PY_MINOR=13

# Arch packages. Official repos:
PAC_REQUIRED=(
    python python-build python-installer python-hatchling python-hatch-vcs python-pillow git
    libnotify wl-clipboard grim slurp swappy cliphist fuzzel wlr-randr ffmpeg dconf power-profiles-daemon
    curl xdg-utils psmisc
)
# AUR:
AUR_REQUIRED=(python-materialyoucolor)
# Optional extras:
PAC_OPTIONAL=(gpu-screen-recorder dart-sass adw-gtk-theme)
AUR_OPTIONAL=(papirus-folders)

ASSUME_YES=0
SKIP_DEPS=0
WITH_OPTIONAL=0
NO_PATH=0
UNINSTALL=0
DRY_RUN=0
SUDO=""

usage() {
    cat <<EOF
Usage: ./install.sh [options]

  -y, --yes            Non-interactive (answer yes, pass --noconfirm to package managers)
      --skip-deps      Do not check or install dependencies
      --with-optional  Install optional runtime packages automatically (Arch)
      --prefix <dir>   Install prefix (default: ~/.local)
      --python <bin>   Python interpreter to build & install with (bypasses active venv)
      --no-path        Do not modify shell RC files or fish_user_paths
      --uninstall      Remove installed caelestia binary, site-packages, and fish completions
      --dry-run        Print what would run without changing anything
  -h, --help           Show this help

Installs to <prefix>/bin/caelestia (default: ~/.local/bin/caelestia).
Supported for automatic dependency install: Arch Linux and derivatives (pacman + yay/paru).
Other distros: dependencies are verified and missing ones are reported.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --skip-deps) SKIP_DEPS=1 ;;
        --with-optional) WITH_OPTIONAL=1 ;;
        --no-path) NO_PATH=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --prefix)
            [ $# -ge 2 ] || die "--prefix requires a directory argument."
            PREFIX="$2"
            shift
            ;;
        --prefix=*) PREFIX="${1#--prefix=}" ;;
        --python)
            [ $# -ge 2 ] || die "--python requires an interpreter argument."
            PYTHON_BIN="$2"
            shift
            ;;
        --python=*) PYTHON_BIN="${1#--python=}" ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

[ -n "$PREFIX" ] || die "--prefix cannot be empty."
[ "${EUID:-$(id -u)}" -ne 0 ] || die "Do not run as root. The script uses sudo/doas only where needed."

detect_priv_exec() {
    if command -v sudo >/dev/null 2>&1; then
        SUDO=sudo
    elif command -v doas >/dev/null 2>&1; then
        SUDO=doas
    else
        SUDO=""
    fi
}
detect_priv_exec

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s[dry-run]%s %s\n' "$C_Y" "$C_0" "$*"
    else
        "$@"
    fi
}

run_priv() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s[dry-run]%s %s %s\n' "$C_Y" "$C_0" "${SUDO:-sudo}" "$*"
    else
        [ -n "$SUDO" ] || die "Neither sudo nor doas is installed; cannot execute privileged command: $*"
        "$SUDO" "$@"
    fi
}

confirm() {
    local prompt="$1" def="${2:-n}" reply hint
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ "$def" = y ] && hint="[Y/n]" || hint="[y/N]"
    if ! (: </dev/tty) 2>/dev/null; then
        [ "$def" = y ]
        return
    fi
    read -r -p "$prompt $hint " reply </dev/tty || reply=""
    reply="${reply:-$def}"
    [[ "$reply" =~ ^[Yy] ]]
}

IS_ARCH=0
command -v pacman >/dev/null 2>&1 && IS_ARCH=1
AUR_HELPER=""
YES_FLAG=()
[ "$ASSUME_YES" -eq 1 ] && YES_FLAG=(--noconfirm)

resolve_python() {
    if [ -n "$PYTHON_BIN" ]; then
        if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
            PYTHON_BIN="$(command -v "$PYTHON_BIN")"
        elif [ ! -x "$PYTHON_BIN" ]; then
            die "Specified Python interpreter not found or not executable: $PYTHON_BIN"
        fi
        return 0
    fi

    local search_path="$PATH" p filtered=""
    if [ -n "${VIRTUAL_ENV:-}" ] || [ -n "${CONDA_PREFIX:-}" ]; then
        warn "Active virtual/conda environment detected; searching system PATH for Python (use --python to override)."
        local IFS=':'
        for p in $PATH; do
            [ -n "${VIRTUAL_ENV:-}" ] && [ "$p" = "$VIRTUAL_ENV/bin" ] && continue
            [ -n "${CONDA_PREFIX:-}" ] && [ "$p" = "$CONDA_PREFIX/bin" ] && continue
            filtered="${filtered:+$filtered:}$p"
        done
        search_path="$filtered"
    fi

    local cand
    for cand in python3 python; do
        if p="$(PATH="$search_path" command -v "$cand" 2>/dev/null)"; then
            PYTHON_BIN="$p"
            return 0
        fi
    done
    for cand in /usr/bin/python3 /usr/bin/python; do
        if [ -x "$cand" ]; then
            PYTHON_BIN="$cand"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    echo "=== Uninstalling vacuited-cli ==="
    confirm "Remove caelestia CLI from $PREFIX and fish completions?" y || exit 0

    if [ -e "$PREFIX/bin/caelestia" ] || [ -L "$PREFIX/bin/caelestia" ]; then
        info "Removing $PREFIX/bin/caelestia"
        run rm -f "$PREFIX/bin/caelestia"
    fi

    local sp d
    for sp in "$PREFIX"/lib/python3.*/site-packages "$PREFIX"/lib64/python3.*/site-packages; do
        [ -d "$sp" ] || continue
        if [ -d "$sp/caelestia" ]; then
            info "Removing $sp/caelestia"
            run rm -rf "$sp/caelestia"
        fi
        shopt -s nullglob
        for d in "$sp"/caelestia-*.dist-info; do
            info "Removing $d"
            run rm -rf "$d"
        done
        shopt -u nullglob
    done

    if [ -e "$CONFIG_HOME/fish/completions/caelestia.fish" ]; then
        info "Removing $CONFIG_HOME/fish/completions/caelestia.fish"
        run rm -f "$CONFIG_HOME/fish/completions/caelestia.fish"
    fi

    log "vacuited-cli uninstalled."
    exit 0
}

if [ "$UNINSTALL" -eq 1 ]; then
    do_uninstall
fi

echo "=== Installing vacuited-cli ==="
[ -f "$SCRIPT_DIR/pyproject.toml" ] && [ -d "$SCRIPT_DIR/src/caelestia" ] || die "Run this script from inside the cli repository."

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

pac_missing() { pacman -T "$@" 2>/dev/null || true; }

detect_aur_helper() {
    local h
    for h in paru yay; do
        if command -v "$h" >/dev/null 2>&1; then AUR_HELPER="$h"; return 0; fi
    done
    return 1
}

bootstrap_aur_helper() {
    warn "No AUR helper (paru/yay) found, but AUR packages are required."
    confirm "Build and install yay-bin from the AUR now?" y || die "Install an AUR helper (yay or paru) and re-run."
    run_priv pacman -S --needed "${YES_FLAG[@]}" git base-devel
    if [ "$DRY_RUN" -eq 1 ]; then
        run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "<tmp>/yay-bin"
        info "[dry-run] would build and install yay-bin via makepkg -si"
    else
        local tmp
        tmp="$(mktemp -d)"
        CLEANUP_PATHS+=("$tmp")
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && makepkg -si "${YES_FLAG[@]}")
    fi
    AUR_HELPER=yay
}

# Strip empty lines from a list passed on stdin into the named array
read_list() {
    local -n _out="$1"
    local line
    _out=()
    while IFS= read -r line; do
        [ -n "$line" ] && _out+=("$line")
    done
}

install_deps_arch() {
    local pac_need=() aur_need=() opt_pac=() opt_aur=()

    read_list pac_need < <(pac_missing "${PAC_REQUIRED[@]}")
    read_list aur_need < <(pac_missing "${AUR_REQUIRED[@]}")

    if [ ${#pac_need[@]} -eq 0 ] && [ ${#aur_need[@]} -eq 0 ]; then
        log "All required dependencies are installed."
    else
        [ ${#pac_need[@]} -gt 0 ] && info "Missing (official repos): ${pac_need[*]}"
        [ ${#aur_need[@]} -gt 0 ] && info "Missing (AUR): ${aur_need[*]}"
        confirm "Install the missing packages?" y || die "Cannot continue without required dependencies."

        if [ ${#pac_need[@]} -gt 0 ]; then
            run_priv pacman -S --needed "${YES_FLAG[@]}" "${pac_need[@]}"
        fi
        if [ ${#aur_need[@]} -gt 0 ]; then
            detect_aur_helper || bootstrap_aur_helper
            run "$AUR_HELPER" -S --needed "${YES_FLAG[@]}" "${aur_need[@]}"
        fi
    fi

    read_list opt_pac < <(pac_missing "${PAC_OPTIONAL[@]}")
    read_list opt_aur < <(pac_missing "${AUR_OPTIONAL[@]}")
    if [ $(( ${#opt_pac[@]} + ${#opt_aur[@]} )) -gt 0 ]; then
        info "Optional extras not installed: ${opt_pac[*]-} ${opt_aur[*]-}"
        info "  gpu-screen-recorder: screen recording | dart-sass: Discord theming | adw-gtk-theme: GTK theme | papirus-folders: folder tinting"
        local do_opt=0
        if [ "$WITH_OPTIONAL" -eq 1 ]; then
            do_opt=1
        elif [ "$ASSUME_YES" -eq 0 ] && confirm "Install optional extras too?" n; then
            do_opt=1
        fi
        if [ "$do_opt" -eq 1 ]; then
            if [ ${#opt_pac[@]} -gt 0 ]; then
                run_priv pacman -S --needed "${YES_FLAG[@]}" "${opt_pac[@]}"
            fi
            if [ ${#opt_aur[@]} -gt 0 ]; then
                detect_aur_helper || bootstrap_aur_helper
                run "$AUR_HELPER" -S --needed "${YES_FLAG[@]}" "${opt_aur[@]}"
            fi
        fi
    fi
}

verify_prereqs() {
    local missing=() m rt rt_missing=()
    resolve_python || { err "python3/python not found."; return 1; }

    if ! "$PYTHON_BIN" -c "import sys; sys.exit(0 if sys.version_info >= ($MIN_PY_MAJOR, $MIN_PY_MINOR) else 1)"; then
        err "Python >= $MIN_PY_MAJOR.$MIN_PY_MINOR is required (found $("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])') at $PYTHON_BIN)."
        return 1
    fi

    for m in build installer hatchling hatch_vcs PIL materialyoucolor; do
        "$PYTHON_BIN" -c "import $m" 2>/dev/null || missing+=("python module: $m")
    done
    if [ -e "$SCRIPT_DIR/.git" ]; then
        command -v git >/dev/null 2>&1 || missing+=("command: git")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        err "Missing prerequisites:"
        printf '    - %s\n' "${missing[@]}" >&2
        [ "$IS_ARCH" -eq 1 ] || err "Install the equivalents for your distro (e.g. via your package manager or a venv), then re-run."
        return 1
    fi

    if [ "$IS_ARCH" -eq 0 ] || [ "$SKIP_DEPS" -eq 1 ]; then
        for rt in notify-send wl-copy grim slurp swappy cliphist fuzzel wlr-randr ffmpeg dconf powerprofilesctl curl xdg-open killall; do
            command -v "$rt" >/dev/null 2>&1 || rt_missing+=("$rt")
        done
        if [ ${#rt_missing[@]} -gt 0 ]; then
            warn "Missing runtime CLI tools (some subcommands may not work): ${rt_missing[*]}"
        fi
    fi

    log "Prerequisites OK (Python $("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])') at $PYTHON_BIN)."
}

if [ "$SKIP_DEPS" -eq 1 ]; then
    warn "Skipping dependency installation (--skip-deps)."
else
    log "Checking dependencies..."
    if [ "$IS_ARCH" -eq 1 ]; then
        install_deps_arch
    else
        warn "Not an Arch-based system: cannot auto-install packages. Verifying instead."
    fi
fi

if [ "$DRY_RUN" -eq 1 ] && [ "$IS_ARCH" -eq 1 ] && [ "$SKIP_DEPS" -eq 0 ]; then
    verify_prereqs || warn "(dry-run) Prerequisites above would be installed by the steps shown."
else
    verify_prereqs || die "Fix the missing prerequisites and re-run."
fi

# Handle conflicting distro packages (they own /usr/bin/caelestia and shadow $PREFIX/bin/caelestia)
if [ "$IS_ARCH" -eq 1 ]; then
    for pkg in caelestia-cli caelestia-cli-git; do
        if pacman -Qq "$pkg" >/dev/null 2>&1; then
            warn "System package '$pkg' is installed (/usr/bin/caelestia) and conflicts with vacuited-cli."
            if confirm "Remove conflicting package '$pkg' now?" y; then
                run_priv pacman -Rdd "${YES_FLAG[@]}" "$pkg"
            else
                warn "Keeping '$pkg'. Ensure $PREFIX/bin precedes /usr/bin in your PATH."
            fi
        fi
    done
fi

# ---------------------------------------------------------------------------
# Syntax pre-check + Build + Install
# ---------------------------------------------------------------------------

log "Checking Python syntax..."
if [ -n "$PYTHON_BIN" ]; then
    run "$PYTHON_BIN" -m compileall -q "$SCRIPT_DIR/src/caelestia"
fi

log "Building the wheel..."
cd "$SCRIPT_DIR"
BUILD_ARGS=(--wheel --no-isolation)

# Safe hatch-vcs versioning for tarballs, nested parent repos, and shallow clones without tags
git_top="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$git_top" ] && git_top="$(readlink -f "$git_top" 2>/dev/null || printf '%s' "$git_top")"
if [ "$git_top" != "$SCRIPT_DIR" ]; then
    export SETUPTOOLS_SCM_PRETEND_VERSION="${SETUPTOOLS_SCM_PRETEND_VERSION:-1.0.0}"
elif ! git -C "$SCRIPT_DIR" describe --tags --abbrev=0 >/dev/null 2>&1; then
    warn "No reachable git tags found (shallow clone or untagged repo); using fallback version for hatch-vcs."
    export SETUPTOOLS_SCM_PRETEND_VERSION="${SETUPTOOLS_SCM_PRETEND_VERSION:-1.0.0}"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    OUT_DIR="<tmp>/dist"
    run "${PYTHON_BIN:-python3}" -m build "${BUILD_ARGS[@]}" --outdir "$OUT_DIR"
    log "Installing to $PREFIX..."
    run "${PYTHON_BIN:-python3}" -m installer --overwrite-existing --prefix "$PREFIX" "$OUT_DIR/*.whl"
else
    OUT_DIR="$(mktemp -d)"
    CLEANUP_PATHS+=("$OUT_DIR")
    "$PYTHON_BIN" -m build "${BUILD_ARGS[@]}" --outdir "$OUT_DIR"

    shopt -s nullglob
    wheels=("$OUT_DIR"/*.whl)
    shopt -u nullglob
    [ ${#wheels[@]} -eq 1 ] || die "Expected exactly one wheel in $OUT_DIR, found ${#wheels[@]}."

    NEW_DISTINFO="$("$PYTHON_BIN" - "${wheels[0]}" <<'EOF'
import sys, zipfile
names = zipfile.ZipFile(sys.argv[1]).namelist()
print(next(n.split("/")[0] for n in names if ".dist-info/" in n))
EOF
)"
    log "Installing to $PREFIX..."
    "$PYTHON_BIN" -m installer --overwrite-existing --prefix "$PREFIX" "${wheels[0]}"

    # Clean outdated dist-info folders in active site-packages and orphaned installs in older Python minor versions
    SITE_PACKAGES="$("$PYTHON_BIN" - "$PREFIX" <<'EOF'
import sys, sysconfig
p = sys.argv[1]
print(sysconfig.get_path("purelib", vars={"base": p, "platbase": p}))
EOF
)"
    if [ -d "$SITE_PACKAGES" ]; then
        for d in "$SITE_PACKAGES"/caelestia-*.dist-info; do
            [ -e "$d" ] || continue
            if [ "$(basename "$d")" != "$NEW_DISTINFO" ]; then
                info "Removing outdated $(basename "$d")"
                rm -rf "$d"
            fi
        done
    fi

    active_sp_real="$(readlink -f "$SITE_PACKAGES" 2>/dev/null || printf '%s' "$SITE_PACKAGES")"
    for old_sp in "$PREFIX"/lib/python3.*/site-packages "$PREFIX"/lib64/python3.*/site-packages; do
        [ -d "$old_sp" ] || continue
        [ "$(readlink -f "$old_sp" 2>/dev/null || printf '%s' "$old_sp")" = "$active_sp_real" ] && continue
        if [ -d "$old_sp/caelestia" ] || compgen -G "$old_sp/caelestia-*.dist-info" >/dev/null; then
            warn "Found orphaned caelestia install in $old_sp"
            if confirm "Remove orphaned install from $old_sp?" y; then
                rm -rf "$old_sp/caelestia" "$old_sp"/caelestia-*.dist-info
            fi
        fi
    done
fi

# ---------------------------------------------------------------------------
# Completions
# ---------------------------------------------------------------------------

if command -v fish >/dev/null 2>&1 || [ -d "$CONFIG_HOME/fish" ]; then
    log "Installing fish completions..."
    run install -Dm644 "$SCRIPT_DIR/completions/caelestia.fish" "$CONFIG_HOME/fish/completions/caelestia.fish"
    if [ "$DRY_RUN" -eq 0 ] && command -v fish >/dev/null 2>&1; then
        fish -n "$CONFIG_HOME/fish/completions/caelestia.fish" || warn "Fish completion syntax check failed."
    fi
else
    info "fish not found, skipping completions."
fi

# ---------------------------------------------------------------------------
# PATH & Initial State
# ---------------------------------------------------------------------------

ensure_local_bin_in_path() {
    case ":$PATH:" in
        *":$PREFIX/bin:"*) ;;
        *) export PATH="$PREFIX/bin:$PATH" ;;
    esac

    [ "$NO_PATH" -eq 0 ] || return 0

    if command -v fish >/dev/null 2>&1; then
        run fish -c 'contains -- $argv[1] $fish_user_paths; or fish_add_path -U -- $argv[1]' -- "$PREFIX/bin" 2>/dev/null || true
    fi

    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] || continue
        if grep -qF "$PREFIX/bin" "$rc" 2>/dev/null; then
            continue
        fi
        if [ "$PREFIX" = "$HOME/.local" ] && grep -qF '.local/bin' "$rc" 2>/dev/null; then
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            info "[dry-run] would offer to append PATH export ($PREFIX/bin) to $rc"
        elif confirm "Add $PREFIX/bin to PATH in $(basename "$rc")?" n; then
            printf '\nexport PATH="%s/bin:$PATH"\n' "$PREFIX" >> "$rc"
            info "Added $PREFIX/bin to PATH in $(basename "$rc")"
        fi
    done
}

ensure_local_bin_in_path

if [ ! -f "$STATE_HOME/caelestia/scheme.json" ]; then
    info "Initializing default Caelestia color scheme..."
    if [ "$DRY_RUN" -eq 1 ]; then
        run "$PREFIX/bin/caelestia" scheme set -n catppuccin -m dark
    else
        "$PREFIX/bin/caelestia" scheme set -n catppuccin -m dark >/dev/null 2>&1 || true
    fi
fi

# ---------------------------------------------------------------------------
# Verify + Summary
# ---------------------------------------------------------------------------

CLI_VERSION="dry-run"
if [ "$DRY_RUN" -eq 0 ]; then
    [ -x "$PREFIX/bin/caelestia" ] || die "Install check failed: $PREFIX/bin/caelestia missing."
    "$PREFIX/bin/caelestia" -v >/dev/null || die "Install check failed: 'caelestia -v' returned an error."
    "$PREFIX/bin/caelestia" hardware status --json >/dev/null || die "Install check failed: 'caelestia hardware status --json' returned an error."

    CLI_VERSION="$(PYTHONPATH="${SITE_PACKAGES:-}${PYTHONPATH:+:$PYTHONPATH}" "$PYTHON_BIN" -c 'import importlib.metadata; print(importlib.metadata.version("caelestia"))' 2>/dev/null || echo "unknown")"
    log "Installed vacuited-cli $CLI_VERSION ($PREFIX/bin/caelestia)."

    resolved="$(command -v caelestia || true)"
    if [ "$resolved" != "$PREFIX/bin/caelestia" ]; then
        warn "'caelestia' resolves to ${resolved:-nothing} instead of $PREFIX/bin/caelestia. Check your PATH order."
    fi

    cli_git_rev=""
    if command -v git >/dev/null 2>&1; then
        cli_git_top="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
        [ -n "$cli_git_top" ] && cli_git_top="$(readlink -f "$cli_git_top" 2>/dev/null || printf '%s' "$cli_git_top")"
        if [ "$cli_git_top" = "$SCRIPT_DIR" ]; then
            cli_git_rev="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || true)"
        fi
    fi
    if [ -n "$cli_git_rev" ] && [ -n "${PYTHON_BIN:-}" ]; then
        "$PYTHON_BIN" - "$STATE_HOME/vacuited" "$cli_git_rev" "$CLI_VERSION" <<'EOF' >/dev/null 2>&1 || true
import fcntl, json, os, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path

state_dir = Path(sys.argv[1])
commit, version, stamp = sys.argv[2], sys.argv[3], datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
meta_path = state_dir / "install-meta.json"
lock_path = state_dir / ".meta.lock"
state_dir.mkdir(parents=True, exist_ok=True)
with lock_path.open("w", encoding="utf-8") as lock_fh:
    fcntl.flock(lock_fh, fcntl.LOCK_EX)
    try:
        try:
            data = json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            data = {}
        if not isinstance(data, dict):
            data = {}
        data.setdefault("schema", 1)
        data.setdefault("shell", {"commit": "", "pluginCommit": "", "version": "", "installedAt": ""})
        cli = data.get("cli") if isinstance(data.get("cli"), dict) else {}
        cli["commit"] = commit
        if version and version != "unknown":
            cli["version"] = version
        cli["installedAt"] = stamp
        data["cli"] = cli
        data.setdefault("lastCheckedAt", "")
        data.setdefault("justUpdated", None)
        fd, tmp = tempfile.mkstemp(prefix=".install-meta.json.", dir=str(state_dir))
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(data, out, indent=2)
            out.write("\n")
        os.replace(tmp, meta_path)
    finally:
        fcntl.flock(lock_fh, fcntl.LOCK_UN)
EOF
    fi
fi

if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files power-profiles-daemon.service >/dev/null 2>&1 && ! systemctl is-active --quiet power-profiles-daemon.service 2>/dev/null; then
        warn "System service 'power-profiles-daemon.service' is not active (enable with: sudo systemctl enable --now power-profiles-daemon)."
    fi
fi

cat <<EOF

=== Done ===
  CLI Version: $CLI_VERSION
  Binary:      $PREFIX/bin/caelestia
  Completions: $CONFIG_HOME/fish/completions/caelestia.fish

Try:  caelestia -h
EOF

if compgen -G "/sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1_enable" >/dev/null && [ ! -x /usr/local/bin/caelestia-hardware-helper ]; then
    info "HP Victus fan controller detected, but /usr/local/bin/caelestia-hardware-helper is missing."
    info "Run vacuited-shell's install.sh --hardware to install the helper and polkit rule."
fi
