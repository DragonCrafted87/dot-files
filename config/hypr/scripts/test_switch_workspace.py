#!/usr/bin/env python3
"""preferred_monitor ignores headless outputs."""

import importlib.util
import unittest
from pathlib import Path


def load_switch():
    path = Path(__file__).with_name("switch-workspace.py")
    spec = importlib.util.spec_from_file_location("switch_workspace", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


switch = load_switch()


def monitor(name, x_pos, width, physical=None):
    record = {
        "name": name,
        "x": x_pos,
        "y": 0,
        "width": width,
        "height": 1440,
        "disabled": False,
    }
    if physical is not None:
        record["physicalWidth"] = physical[0]
        record["physicalHeight"] = physical[1]
    return record


DESK = [
    monitor("DP-2", 0, 2560, (600, 340)),
    monitor("DP-3", 2560, 3440, (800, 340)),
    monitor("HDMI-A-1", 6000, 2560, (600, 340)),
]


class PreferredMonitorTests(unittest.TestCase):
    def test_desk_midpoint_is_the_center_panel(self):
        self.assertEqual(switch.preferred_monitor(DESK), "DP-3")

    def test_headless_past_hdmi_does_not_move_the_midpoint(self):
        headless = monitor("HEADLESS-3", 12000, 2560, (0, 0))
        self.assertEqual(switch.preferred_monitor(DESK + [headless]), "DP-3")

    def test_headless_name_is_enough_when_a_panel_size_is_set(self):
        named = monitor("HEADLESS-3", 12000, 2560, (600, 340))
        self.assertTrue(switch.is_headless_monitor(named))
        self.assertEqual(switch.preferred_monitor(DESK + [named]), "DP-3")

    def test_zero_panel_size_is_headless_without_that_name(self):
        virtual = monitor("virt", 12000, 2560, (0, 0))
        self.assertTrue(switch.is_headless_monitor(virtual))
        self.assertEqual(switch.preferred_monitor(DESK + [virtual]), "DP-3")

    def test_missing_panel_size_keeps_a_named_output(self):
        bare = [monitor(item["name"], item["x"], item["width"]) for item in DESK]
        self.assertFalse(switch.is_headless_monitor(bare[1]))
        self.assertEqual(switch.preferred_monitor(bare), "DP-3")

    def test_no_monitors(self):
        self.assertIsNone(switch.preferred_monitor([]))

    def test_only_headless(self):
        self.assertIsNone(
            switch.preferred_monitor([monitor("HEADLESS-1", 0, 1920, (0, 0))])
        )

    def test_single_output(self):
        self.assertEqual(switch.preferred_monitor([DESK[2]]), "HDMI-A-1")

    def test_gap_between_equal_panels_picks_the_left_one(self):
        panels = [DESK[0], DESK[2]]
        self.assertEqual(switch.preferred_monitor(panels), "DP-2")

    def test_two_containers_pick_the_wider_one(self):
        panels = [
            monitor("narrow", 0, 4000, (600, 340)),
            monitor("wide", 1000, 5000, (700, 340)),
        ]
        self.assertEqual(switch.preferred_monitor(panels), "wide")

    def test_disabled_monitor_is_ignored(self):
        disabled = dict(DESK[1])
        disabled["disabled"] = True
        self.assertEqual(switch.preferred_monitor([DESK[0], disabled, DESK[2]]), "DP-2")


if __name__ == "__main__":
    unittest.main()
