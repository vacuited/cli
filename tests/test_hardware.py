import json
import unittest
from unittest.mock import MagicMock, mock_open, patch
from pathlib import Path
from argparse import Namespace

from caelestia.subcommands import hardware
from caelestia.parser import parse_args


class TestHardwareCommand(unittest.TestCase):
    def test_get_status_dict(self):
        hw = hardware.HardwareManager()
        with patch.object(hw, "get_profile", return_value="performance"), \
             patch.object(hw, "get_fan_mode", return_value="auto"), \
             patch.object(hw, "get_fan_rpms", return_value=(3200, 2700)), \
             patch.object(hw, "get_refresh_rate", return_value=144), \
             patch.object(hw, "get_cpu_temp", return_value=54), \
             patch.object(hw, "get_gpu_temp_and_power", return_value=(40, 2.65, "D3 Sleep")), \
             patch.object(hw, "get_turbo", return_value=True):
            status = hw.get_status()
            self.assertEqual(status["profile"], "performance")
            self.assertEqual(status["fanMode"], "auto")
            self.assertEqual(status["fan1Rpm"], 3200)
            self.assertEqual(status["fan2Rpm"], 2700)
            self.assertEqual(status["refreshRate"], 144)
            self.assertEqual(status["cpuTemp"], 54)
            self.assertEqual(status["gpuTemp"], 40)
            self.assertEqual(status["gpuPower"], 2.65)
            self.assertEqual(status["gpuState"], "D3 Sleep")
            self.assertTrue(status["turbo"])

    def test_set_fan_mode_validation(self):
        hw = hardware.HardwareManager()
        with self.assertRaises(ValueError):
            hw.set_fan_mode("invalid")

    def test_set_profile_validation(self):
        hw = hardware.HardwareManager()
        with patch.object(hw, "get_profile_choices", return_value=["quiet", "balanced", "performance"]):
            with self.assertRaises(ValueError):
                hw.set_profile("super-fast")

    def test_command_status_json(self):
        args = Namespace(action="status", target=None, json=True)
        cmd = hardware.Command(args)
        mock_data = {
            "profile": "balanced",
            "fanMode": "auto",
            "fan1Rpm": 0,
            "fan2Rpm": 0,
            "refreshRate": 60,
            "cpuTemp": 50,
            "gpuTemp": 40,
            "gpuPower": 2.5,
            "gpuState": "D3 Sleep",
            "turbo": True,
        }
        with patch.object(cmd.hw, "get_status", return_value=mock_data), \
             patch("builtins.print") as mock_print:
            cmd.run()
            mock_print.assert_called_once()
            output = mock_print.call_args[0][0]
            data = json.loads(output)
            self.assertEqual(data["profile"], "balanced")
            self.assertEqual(data["cpuTemp"], 50)
            self.assertTrue(data["turbo"])

    def test_parser_hardware_commands(self):
        with patch("sys.argv", ["caelestia", "hardware", "profile", "balanced"]):
            parser, args = parse_args()
            self.assertEqual(args.cls, hardware.Command)
            self.assertEqual(args.action, "profile")
            self.assertEqual(args.target, "balanced")

        with patch("sys.argv", ["caelestia", "hardware", "status", "--json"]):
            parser, args = parse_args()
            self.assertEqual(args.action, "status")
            self.assertTrue(args.json)

        with patch("sys.argv", ["caelestia", "hardware", "turbo", "on"]):
            parser, args = parse_args()
            self.assertEqual(args.action, "turbo")
            self.assertEqual(args.target, "on")


if __name__ == "__main__":
    unittest.main()
