#!/usr/bin/env bash
# install.sh — Build and install the vacuited CLI (`caelestia`)
#
# What it does:
#   1. Checks dependencies (auto-installs missing ones on Arch-based distros)
#   2. Builds the wheel and installs it to ~/.local (no sudo for the CLI itself)
#   3. Installs fish completions
#   4. Removes outdated caelestia dist-info folders and verifies the result

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PREFIX="${HOME}/.local"
MIN_PY_MAJOR=3
MIN_PY_MINOR=13

# Arch packages. Official repos:
PAC_REQUIRED=(
    python python-build python-installer python-hatchling python-hatch-vcs python-pillow git
    libnotify wl-clipboard grim slurp swappy cliphist fuzzel wlr-randr ffmpeg dconf power-profiles-daemon
)
# AUR:
AUR_REQUIRED=(python-materialyoucolor)
# Optional extras (offered, default no):
PAC_OPTIONAL=(gpu-screen-recorder dart-sass)
AUR_OPTIONAL=(papirus-folders)

ASSUME_YES=0
SKIP_DEPS=0
DRY_RUN=0
SUDO=sudo

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

usage() {
    cat <<EOF
Usage: ./install.sh [options]

  -y, --yes        Non-interactive (answer yes, pass --noconfirm to package managers)
      --skip-deps  Do not check or install dependencies
      --dry-run    Print what would run without changing anything
  -h, --help       Show this help

Installs to ~/.local/bin/caelestia. Make sure ~/.local/bin is in your PATH.
Supported for automatic dependency install: Arch Linux and derivatives (pacman + yay/paru).
Other distros: dependencies are verified and missing ones are reported.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --skip-deps) SKIP_DEPS=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

[ "$(id -u)" -ne 0 ] || die "Do not run as root. The script calls sudo only where needed."

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s[dry-run]%s %s\n' "$C_Y" "$C_0" "$*"
    else
        "$@"
    fi
}

confirm() {
    local prompt="$1" def="${2:-n}" reply hint
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ "$def" = y ] && hint="[Y/n]" || hint="[y/N]"
    if [ ! -r /dev/tty ]; then
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
    run $SUDO pacman -S --needed "${YES_FLAG[@]}" git base-devel
    local tmp
    tmp="$(mktemp -d)"
    run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    if [ "$DRY_RUN" -eq 1 ]; then
        info "[dry-run] would run makepkg -si in $tmp/yay-bin"
    else
        (cd "$tmp/yay-bin" && makepkg -si "${YES_FLAG[@]}")
    fi
    rm -rf "$tmp"
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
            run $SUDO pacman -S --needed "${YES_FLAG[@]}" "${pac_need[@]}"
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
        info "  gpu-screen-recorder: screen recording | dart-sass: Discord theming | papirus-folders: folder tinting"
        if [ "$ASSUME_YES" -eq 0 ] && confirm "Install optional extras too?" n; then
            if [ ${#opt_pac[@]} -gt 0 ]; then
                run $SUDO pacman -S --needed "${YES_FLAG[@]}" "${opt_pac[@]}"
            fi
            if [ ${#opt_aur[@]} -gt 0 ]; then
                detect_aur_helper || bootstrap_aur_helper
                run "$AUR_HELPER" -S --needed "${YES_FLAG[@]}" "${opt_aur[@]}"
            fi
        fi
    fi
}

verify_prereqs() {
    local missing=() c m
    command -v python >/dev/null 2>&1 || { err "python not found."; return 1; }

    if ! python -c "import sys; sys.exit(0 if sys.version_info >= ($MIN_PY_MAJOR, $MIN_PY_MINOR) else 1)"; then
        err "Python >= $MIN_PY_MAJOR.$MIN_PY_MINOR is required (found $(python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))."
        return 1
    fi

    for m in build installer PIL materialyoucolor; do
        python -c "import $m" 2>/dev/null || missing+=("python module: $m")
    done
    for c in git; do
        command -v "$c" >/dev/null 2>&1 || missing+=("command: $c")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        err "Missing prerequisites:"
        printf '    - %s\n' "${missing[@]}" >&2
        [ "$IS_ARCH" -eq 1 ] || err "Install the equivalents for your distro (e.g. via your package manager or a venv), then re-run."
        return 1
    fi
    log "Prerequisites OK (Python $(python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))."
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

# Warn about conflicting distro packages (they own /usr/bin/caelestia)
if [ "$IS_ARCH" -eq 1 ]; then
    for pkg in caelestia-cli caelestia-cli-git; do
        if pacman -Qq "$pkg" >/dev/null 2>&1; then
            warn "Package '$pkg' is installed and may shadow this build. Remove it with: sudo pacman -Rdd $pkg"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Build + install
# ---------------------------------------------------------------------------

log "Building the wheel..."
cd "$SCRIPT_DIR"
run rm -rf dist
BUILD_ARGS=(--wheel)
if python -c "import hatchling, hatch_vcs" 2>/dev/null; then
    BUILD_ARGS+=(--no-isolation)
fi
# hatch-vcs needs git metadata; fall back to a fixed version for tarballs
if ! git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    export SETUPTOOLS_SCM_PRETEND_VERSION="${SETUPTOOLS_SCM_PRETEND_VERSION:-1.0.0}"
fi
run python -m build "${BUILD_ARGS[@]}"

log "Installing to $PREFIX..."
if [ "$DRY_RUN" -eq 1 ]; then
    run python -m installer --overwrite-existing --prefix "$PREFIX" "dist/*.whl"
    NEW_DISTINFO="caelestia-*.dist-info"
else
    shopt -s nullglob
    wheels=(dist/*.whl)
    shopt -u nullglob
    [ ${#wheels[@]} -eq 1 ] || die "Expected exactly one wheel in dist/, found ${#wheels[@]}."
    NEW_DISTINFO="$(python - "${wheels[0]}" <<'EOF'
import sys, zipfile
names = zipfile.ZipFile(sys.argv[1]).namelist()
print(next(n.split("/")[0] for n in names if ".dist-info/" in n))
EOF
)"
    python -m installer --overwrite-existing --prefix "$PREFIX" "${wheels[0]}"
fi

# Remove outdated dist-info folders from previous versions
SITE_PACKAGES="$(python -c "import sysconfig; print(sysconfig.get_path('purelib', vars={'base': '$PREFIX', 'platbase': '$PREFIX'}))")"
if [ "$DRY_RUN" -eq 0 ] && [ -d "$SITE_PACKAGES" ]; then
    for d in "$SITE_PACKAGES"/caelestia-*.dist-info; do
        [ -e "$d" ] || continue
        if [ "$(basename "$d")" != "$NEW_DISTINFO" ]; then
            info "Removing outdated $(basename "$d")"
            rm -rf "$d"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Completions
# ---------------------------------------------------------------------------

if command -v fish >/dev/null 2>&1 || [ -d "$CONFIG_HOME/fish" ]; then
    log "Installing fish completions..."
    run mkdir -p "$CONFIG_HOME/fish/completions"
    run cp "$SCRIPT_DIR/completions/caelestia.fish" "$CONFIG_HOME/fish/completions/caelestia.fish"
else
    info "fish not found, skipping completions."
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

if [ "$DRY_RUN" -eq 0 ]; then
    [ -x "$PREFIX/bin/caelestia" ] || die "Install check failed: $PREFIX/bin/caelestia missing."
    "$PREFIX/bin/caelestia" -v >/dev/null || die "Install check failed: 'caelestia -v' returned an error."
    log "Installed: $("$PREFIX/bin/caelestia" -v 2>&1 | head -n1)"
    resolved="$(command -v caelestia || true)"
    if [ "$resolved" != "$PREFIX/bin/caelestia" ]; then
        case ":$PATH:" in
            *":$PREFIX/bin:"*) warn "'caelestia' resolves to ${resolved:-nothing}, not $PREFIX/bin/caelestia. Check your PATH order." ;;
            *) warn "Add $PREFIX/bin to your PATH:  fish_add_path ~/.local/bin  (fish)  |  export PATH=\"\$HOME/.local/bin:\$PATH\"  (bash/zsh)" ;;
        esac
    fi
fi

echo
echo "=== Done ==="
echo "Try:  caelestia -h"
echo "HP Victus hardware control (optional) needs the helper installed by the shell repo's install.sh."

