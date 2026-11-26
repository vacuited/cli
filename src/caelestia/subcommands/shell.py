import json
import os
import shutil
import signal
import time
from pathlib import Path
import subprocess
from argparse import Namespace

from caelestia.utils.io import fatal, warn
from caelestia.utils.paths import c_cache_dir, config_dir


class Command:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def run(self) -> None:
        if self.args.show:
            # Print the ipc
            self.print_ipc()
        elif self.args.log:
            # Print the log
            self.print_log()
        elif self.args.kill:
            # Kill the shell
            self.stop_instances()
        elif self.args.restart:
            # Restart the shell. Wait for the old instances to exit first,
            # otherwise `-n` will silently skip the relaunch
            self.stop_instances()
            self.start_shell()
        elif self.args.message:
            # Send a message
            self.message(*self.args.message)
        else:
            # Start the shell
            self.start_shell()

    def shell(self, *args: str) -> str:
        return subprocess.check_output(["qs", "-c", "caelestia", *args], text=True)

    def _find_caelestia_qml_dir(self) -> Path | None:
        candidates: list[Path] = []
        for env_key in ("QML_IMPORT_PATH", "QML2_IMPORT_PATH"):
            raw = os.environ.get(env_key, "")
            for part in raw.split(":"):
                if part:
                    candidates.append(Path(part))
        candidates.extend([Path("/usr/lib/qt6/qml"), Path("/usr/lib64/qt6/qml")])

        for base in candidates:
            if (base / "Caelestia" / "qmldir").is_file():
                return base / "Caelestia"

        for qp in ("qtpaths6", "qtpaths-qt6", "/usr/lib/qt6/bin/qtpaths6", "/usr/lib64/qt6/bin/qtpaths6"):
            exe = shutil.which(qp) if "/" not in qp else (qp if os.access(qp, os.X_OK) else None)
            if not exe:
                continue
            proc = subprocess.run([exe, "--query", "QT_INSTALL_QML"], capture_output=True, text=True, check=False)
            if proc.returncode == 0 and proc.stdout.strip():
                qml_dir = Path(proc.stdout.strip()) / "Caelestia"
                if (qml_dir / "qmldir").is_file():
                    return qml_dir
            break
        return None

    def preflight_check(self) -> None:
        try:
            qs_root = config_dir / "quickshell"
            root_qml = qs_root / "shell.qml"
            if root_qml.exists() or root_qml.is_symlink():
                warn(f"Found {root_qml}; Quickshell treats root shell.qml as default and ignores 'quickshell/caelestia'.")

            qs_dir = qs_root / "caelestia"
            if not qs_dir.exists():
                return

            shell_qml = qs_dir / "shell.qml"
            is_vacuited_qml = (qs_dir / "services" / "Skwd.qml").is_file()
            if not is_vacuited_qml and shell_qml.is_file():
                is_vacuited_qml = "vacuited/shell" in shell_qml.read_text(encoding="utf-8", errors="ignore")
            if not is_vacuited_qml:
                return

            plugin_dir = self._find_caelestia_qml_dir()
            if plugin_dir is None:
                warn("Caelestia C++ QML plugin not found. Re-run ./install.sh from your vacuited/shell repo.")
                return

            if not (plugin_dir / ".vacuited-plugin").is_file() and not (plugin_dir / "Images" / "qmldir").is_file():
                warn(
                    f"Plugin mismatch (split-brain): {qs_dir} has vacuited-shell QML, "
                    f"but {plugin_dir} appears to be upstream caelestia-shell. "
                    f"Re-run vacuited/shell ./install.sh to rebuild the plugin, or remove {qs_dir} to use upstream."
                )
                return

            ldd_bin = shutil.which("ldd")
            if not ldd_bin:
                return

            sos = sorted((plugin_dir / "lib").glob("*.so"))
            if not sos:
                return

            proc = subprocess.run([ldd_bin, *(str(p) for p in sos)], capture_output=True, text=True, check=False)
            core_missing: dict[str, list[str]] = {}
            qs_missing: list[str] = []
            current_so = sos[0].name if len(sos) == 1 else ""

            for line in proc.stdout.splitlines():
                stripped = line.strip()
                if stripped.endswith(":") and stripped.startswith("/"):
                    current_so = Path(stripped[:-1]).name
                    continue
                if "=> not found" in stripped:
                    soname = stripped.split("=>", 1)[0].strip()
                    if "quickshare" in current_so:
                        if soname not in qs_missing:
                            qs_missing.append(soname)
                    else:
                        core_missing.setdefault(current_so or "plugin", [])
                        if soname not in core_missing[current_so or "plugin"]:
                            core_missing[current_so or "plugin"].append(soname)

            if core_missing:
                details = "; ".join(f"{so}: {', '.join(libs)}" for so, libs in core_missing.items())
                all_libs = {lib for libs in core_missing.values() for lib in libs}
                if any("libcava" in lib or "libsndio" in lib for lib in all_libs):
                    hint = "Rebuild libcava first (e.g. 'paru -S --rebuild libcava'), then re-run vacuited/shell ./install.sh."
                else:
                    hint = "Re-run ./install.sh from your vacuited/shell repo to rebuild the plugin."
                warn(f"Missing shared library dependency in Caelestia plugin ({details}). {hint}")

            if qs_missing:
                warn(
                    f"Optional Quick Share plugin missing {', '.join(qs_missing)}; "
                    "Quick Share will stay disabled until vacuited/shell ./install.sh is re-run."
                )
        except Exception:
            pass

    def start_shell(self) -> None:
        self.preflight_check()

        # Hardware Decoder Injection
        try:
            decoder_file = Path(os.path.expanduser("~/.cache/caelestia/hwDecoder.txt"))
            if decoder_file.exists():
                decoder = decoder_file.read_text().strip()
                if decoder and decoder.lower() != "auto":
                    os.environ["QT_FFMPEG_DECODING_HW_DEVICE_TYPES"] = decoder
        except Exception:
            pass

        os.environ.setdefault(
            "MALLOC_CONF",
            "narenas:4,background_thread:true,dirty_decay_ms:2000,muzzy_decay_ms:0,thp:never",
        )

        args = ["qs", "-c", "caelestia", "-n"]
        if self.args.log_rules:
            args.extend(["--log-rules", self.args.log_rules])
        if self.args.daemon:
            args.append("-d")
            subprocess.run(args)
        else:
            shell = subprocess.Popen(args, stdout=subprocess.PIPE, universal_newlines=True)

            # Ensure stdout is not None for the type checker
            if shell.stdout:
                for line in shell.stdout:
                    if self.filter_log(line):
                        print(line, end="")

    def list_instances(self) -> list[dict]:
        proc = subprocess.run(["qs", "-c", "caelestia", "list", "-j"], check=False, capture_output=True, text=True)
        if proc.returncode != 0:
            fatal(f"failed to list shell instances: {(proc.stderr or proc.stdout).strip()}")

        # `qs list` exits 0 and prints a plain text notice instead of JSON when
        # there are no instances, so only treat that exact case as empty
        out = proc.stdout.strip()
        if out.startswith("No running instances"):
            return []

        try:
            return json.loads(out)
        except json.JSONDecodeError:
            fatal(f"failed to parse shell instance list: {out}")

    def instance_pids(self) -> list[int]:
        return [instance["pid"] for instance in self.list_instances()]

    def wait_for_exit(self, timeout: float) -> bool:
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if not self.list_instances():
                return True
            time.sleep(0.1)
        return False

    def stop_instances(self) -> None:
        pids = self.instance_pids()
        if not pids:
            return

        # Without `--pid`, `qs kill` only kills one instance, so ask each one to
        # exit. A kill that fails is not fatal here: the force kill below is the
        # fallback for any instance that does not go away.
        for pid in pids:
            subprocess.run(["qs", "-c", "caelestia", "kill", "--pid", str(pid)], check=False, stdout=subprocess.DEVNULL)

        # Teardown is not instant, so wait for the instances to actually disappear
        if self.wait_for_exit(5):
            return

        # Some instances are stuck; force kill them to ensure they are stopped
        warn("shell did not exit gracefully, killing")
        for pid in self.instance_pids():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

        if not self.wait_for_exit(2):
            fatal("an instance of the shell is still running")

    def filter_log(self, line: str) -> bool:
        return f"Cannot open: file://{c_cache_dir}/imagecache/" not in line

    def print_ipc(self) -> None:
        print(self.shell("ipc", "show"), end="")

    def print_log(self) -> None:
        if self.args.log_rules:
            log = self.shell("log", "-r", self.args.log_rules)
        else:
            log = self.shell("log")
        # FIXME: remove when logging rules are added/warning is removed
        for line in log.splitlines():
            if self.filter_log(line):
                print(line)

    def message(self, *args: list[str]) -> None:
        print(self.shell("ipc", "call", *args), end="")
