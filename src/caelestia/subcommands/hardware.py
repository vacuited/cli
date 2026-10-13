import json
import os
import re
import shlex
import subprocess
from argparse import Namespace
from pathlib import Path
from typing import Any, Tuple

from caelestia.utils.io import fatal, info, warn


class HardwareManager:
    PROFILE_PATH = Path("/sys/firmware/acpi/platform_profile")
    PROFILE_CHOICES_PATH = Path("/sys/firmware/acpi/platform_profile_choices")
    NO_TURBO_PATH = Path("/sys/devices/system/cpu/intel_pstate/no_turbo")
    HELPER_PATH = Path("/usr/local/bin/caelestia-hardware-helper")

    def find_hp_hwmon(self) -> Path | None:
        base = Path("/sys/devices/platform/hp-wmi/hwmon")
        if not base.exists():
            return None
        for entry in base.glob("hwmon*"):
            if entry.is_dir() and (entry / "pwm1_enable").exists():
                return entry
        return None

    def get_profile_choices(self) -> list[str]:
        if self.PROFILE_CHOICES_PATH.exists():
            try:
                return self.PROFILE_CHOICES_PATH.read_text().strip().split()
            except Exception:
                pass
        return ["quiet", "cool", "balanced", "performance"]

    def get_profile(self) -> str:
        if self.PROFILE_PATH.exists():
            try:
                return self.PROFILE_PATH.read_text().strip()
            except Exception:
                pass
        return "unknown"

    def set_profile(self, profile: str) -> None:
        choices = self.get_profile_choices()
        if profile not in choices:
            choices_str = ", ".join(choices)
            raise ValueError(f"Invalid profile '{profile}'. Supported: {choices_str}")

        mapping = {
            "quiet": "power-saver",
            "balanced": "balanced",
            "performance": "performance",
        }
        if profile in mapping:
            try:
                subprocess.run(["powerprofilesctl", "set", mapping[profile]], check=False)
            except Exception:
                pass

        if self.PROFILE_PATH.exists() and self.PROFILE_PATH.read_text().strip() == profile:
            return

        try:
            self.PROFILE_PATH.write_text(profile)
            return
        except (PermissionError, OSError):
            pass

        helper = self.HELPER_PATH if self.HELPER_PATH.exists() else Path.home() / "retroistickx/projects/vacuited-shell/scripts/caelestia-hardware-helper"
        cmd = ["pkexec", str(helper), "set-profile", profile]
        res = subprocess.run(cmd)
        if res.returncode != 0:
            raise RuntimeError(f"Failed to set platform profile to {profile}.")

        if profile in mapping:
            try:
                subprocess.run(["powerprofilesctl", "set", mapping[profile]], check=False)
            except Exception:
                pass

    def get_fan_mode(self) -> str:
        hwmon = self.find_hp_hwmon()
        if hwmon:
            pwm_file = hwmon / "pwm1_enable"
            if pwm_file.exists():
                try:
                    val = pwm_file.read_text().strip()
                    if val == "0":
                        return "max"
                    return "auto"
                except Exception:
                    pass
        return "auto"

    def set_fan_mode(self, mode: str) -> None:
        if mode not in ("auto", "max"):
            raise ValueError(f"Invalid fan mode '{mode}'. Valid modes: auto, max")

        hwmon = self.find_hp_hwmon()
        if not hwmon:
            raise FileNotFoundError("hp-wmi hwmon device not found.")

        pwm_file = hwmon / "pwm1_enable"
        val = "0" if mode == "max" else "2"

        try:
            pwm_file.write_text(val)
            return
        except (PermissionError, OSError):
            pass

        helper = self.HELPER_PATH if self.HELPER_PATH.exists() else Path.home() / "retroistickx/projects/vacuited-shell/scripts/caelestia-hardware-helper"
        cmd = ["pkexec", str(helper), "set-fan", mode]
        res = subprocess.run(cmd)
        if res.returncode != 0:
            raise RuntimeError(f"Failed to set fan mode to {mode}.")

    def get_fan_rpms(self) -> Tuple[int, int]:
        hwmon = self.find_hp_hwmon()
        fan1, fan2 = 0, 0
        if hwmon:
            f1 = hwmon / "fan1_input"
            f2 = hwmon / "fan2_input"
            if f1.exists():
                try:
                    fan1 = int(f1.read_text().strip())
                except Exception:
                    pass
            if f2.exists():
                try:
                    fan2 = int(f2.read_text().strip())
                except Exception:
                    pass
        return fan1, fan2

    def get_refresh_rate(self) -> int:
        try:
            res = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True)
            if res.returncode == 0:
                data = json.loads(res.stdout)
                if data and isinstance(data, list) and len(data) > 0:
                    raw_hz = data[0].get("refreshRate", 60)
                    return round(float(raw_hz))
        except Exception:
            pass

        try:
            res = subprocess.run(["wlr-randr"], capture_output=True, text=True)
            if res.returncode == 0:
                m = re.search(r"\b(\d+(?:\.\d+)?)\s*Hz\s*\(current\)", res.stdout)
                if m:
                    return round(float(m.group(1)))
        except Exception:
            pass

        return 60

    def set_refresh_rate(self, hz: int) -> None:
        if hz not in (60, 144):
            raise ValueError(f"Unsupported refresh rate {hz}. Valid: 60, 144")

        output = "eDP-1"
        try:
            res = subprocess.run(["wlr-randr"], capture_output=True, text=True)
            if res.returncode == 0:
                m = re.search(r"^([a-zA-Z0-9_-]+)\s+\"", res.stdout, re.MULTILINE)
                if m:
                    output = m.group(1)
        except Exception:
            pass

        try:
            res = subprocess.run(["wlr-randr", "--output", output], capture_output=True, text=True)
            if res.returncode == 0:
                pattern = rf"^\s+(\d+x\d+)\s+px,\s+.*\b({hz}\.\d+)\s*Hz"
                mode_match = None
                for line in res.stdout.splitlines():
                    m = re.search(pattern, line)
                    if m:
                        mode_match = f"{m.group(1)}@{m.group(2)}Hz"
                        break
                if mode_match:
                    subprocess.run(["wlr-randr", "--output", output, "--mode", mode_match], check=False)
                elif hz == 144:
                    subprocess.run(["wlr-randr", "--output", output, "--preferred"], check=False)
        except Exception:
            pass

        cava_conf = Path.home() / ".config/cava/config"
        if cava_conf.exists():
            try:
                content = cava_conf.read_text()
                new_content = re.sub(r"^framerate = .*", f"framerate = {hz}", content, flags=re.MULTILINE)
                cava_conf.write_text(new_content)
                subprocess.run(["pkill", "-USR2", "cava"], check=False)
            except Exception:
                pass

    def get_cpu_temp(self) -> int:
        hwmon_base = Path("/sys/class/hwmon")
        if not hwmon_base.exists():
            return 0
        for h in hwmon_base.glob("hwmon*"):
            name_file = h / "name"
            if name_file.exists() and name_file.read_text().strip() == "coretemp":
                for label_file in h.glob("temp*_label"):
                    try:
                        if "Package" in label_file.read_text():
                            inp = h / label_file.name.replace("_label", "_input")
                            if inp.exists():
                                return round(int(inp.read_text().strip()) / 1000)
                    except Exception:
                        pass
                inp1 = h / "temp1_input"
                if inp1.exists():
                    try:
                        return round(int(inp1.read_text().strip()) / 1000)
                    except Exception:
                        pass
        return 0

    def get_gpu_temp_and_power(self) -> Tuple[int, float, str]:
        try:
            res = subprocess.run(
                ["nvidia-smi", "--query-gpu=temperature.gpu,power.draw,pstate", "--format=csv,noheader,nounits"],
                capture_output=True,
                text=True,
                check=False,
            )
            if res.returncode == 0 and res.stdout.strip():
                parts = [p.strip() for p in res.stdout.strip().split(",")]
                gpu_temp = int(parts[0]) if len(parts) > 0 and parts[0].isdigit() else 0
                gpu_power = float(parts[1]) if len(parts) > 1 and parts[1].replace(".", "", 1).isdigit() else 0.0
                pstate = parts[2] if len(parts) > 2 else ""
                gpu_state = "D3 Sleep" if pstate == "P8" and gpu_power < 5.0 else "Active"
                return gpu_temp, gpu_power, gpu_state
        except Exception:
            pass
        return 0, 0.0, "Suspended"

    def get_turbo(self) -> bool:
        if self.NO_TURBO_PATH.exists():
            try:
                return self.NO_TURBO_PATH.read_text().strip() == "0"
            except Exception:
                pass
        return True

    def set_turbo(self, enabled: bool) -> None:
        val = "0" if enabled else "1"
        try:
            self.NO_TURBO_PATH.write_text(val)
            return
        except (PermissionError, OSError):
            pass

        helper = self.HELPER_PATH if self.HELPER_PATH.exists() else Path.home() / "retroistickx/projects/vacuited-shell/scripts/caelestia-hardware-helper"
        cmd = ["pkexec", str(helper), "set-turbo", "on" if enabled else "off"]
        res = subprocess.run(cmd)
        if res.returncode != 0:
            raise RuntimeError(f"Failed to set turbo state to {'on' if enabled else 'off'}.")

    def get_status(self) -> dict[str, Any]:
        fan1, fan2 = self.get_fan_rpms()
        gpu_temp, gpu_power, gpu_state = self.get_gpu_temp_and_power()
        is_supported = bool(self.find_hp_hwmon() or self.PROFILE_PATH.exists())
        return {
            "supported": is_supported,
            "profile": self.get_profile(),
            "fanMode": self.get_fan_mode(),
            "fan1Rpm": fan1,
            "fan2Rpm": fan2,
            "refreshRate": self.get_refresh_rate(),
            "cpuTemp": self.get_cpu_temp(),
            "gpuTemp": gpu_temp,
            "gpuPower": gpu_power,
            "gpuState": gpu_state,
            "turbo": self.get_turbo(),
        }


class Command:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args
        self.hw = HardwareManager()

    def run(self) -> None:
        action = getattr(self.args, "action", "status") or "status"

        if action == "status":
            status = self.hw.get_status()
            if getattr(self.args, "json", False):
                print(json.dumps(status))
            else:
                print(f"Profile:      {status['profile']}")
                print(f"Fan Mode:     {status['fanMode']}")
                print(f"CPU Fan:      {status['fan1Rpm']} RPM ({status['cpuTemp']}°C)")
                print(f"GPU Fan:      {status['fan2Rpm']} RPM ({status['gpuTemp']}°C, {status['gpuPower']}W, {status['gpuState']})")
                print(f"Refresh Rate: {status['refreshRate']} Hz")
                print(f"Turbo Boost:  {'Enabled' if status['turbo'] else 'Disabled'}")

        elif action == "profile":
            target = getattr(self.args, "target", None)
            if not target or target == "get":
                print(self.hw.get_profile())
            else:
                try:
                    self.hw.set_profile(target)
                    info(f"Platform profile set to {target}")
                except Exception as e:
                    fatal(str(e))

        elif action == "fan":
            target = getattr(self.args, "target", None)
            if not target or target == "get":
                print(self.hw.get_fan_mode())
            else:
                try:
                    self.hw.set_fan_mode(target)
                    info(f"Fan mode set to {target}")
                except Exception as e:
                    fatal(str(e))

        elif action == "refresh":
            target = getattr(self.args, "target", None)
            if not target or target == "get":
                print(f"{self.hw.get_refresh_rate()}Hz")
            else:
                try:
                    hz = int(str(target).replace("Hz", "").replace("hz", ""))
                    self.hw.set_refresh_rate(hz)
                    info(f"Refresh rate set to {hz}Hz")
                except Exception as e:
                    fatal(str(e))

        elif action == "turbo":
            target = getattr(self.args, "target", None)
            if not target or target == "get":
                print("on" if self.hw.get_turbo() else "off")
            else:
                try:
                    enabled = target.lower() in ("on", "enable", "true", "1")
                    self.hw.set_turbo(enabled)
                    info(f"Turbo boost set to {'on' if enabled else 'off'}")
                except Exception as e:
                    fatal(str(e))
        else:
            fatal(f"Unknown action: {action}")
