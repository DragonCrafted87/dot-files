"""Placement rules for the code workspaces."""

import importlib.util
import unittest
from pathlib import Path


def load_switch():
    path = Path(__file__).with_name("switch-workspace.py")
    spec = importlib.util.spec_from_file_location("switch_workspace", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


switch = load_switch()


def monitor(name, x_pos, width, **extra):
    record = {"name": name, "x": x_pos, "y": 0, "width": width, "height": 1440}
    record.update(extra)
    return record


def code_window(address, workspace, **extra):
    record = {
        "address": address,
        "class": "com.microsoft.VSCode",
        "initialClass": "com.microsoft.VSCode",
        "floating": False,
        "mapped": True,
        "workspace": {"id": 11, "name": workspace},
    }
    record.update(extra)
    return record


RUNEWYRM = [
    monitor("DP-2", 0, 2560),
    monitor("DP-3", 2560, 3440),
    monitor("HDMI-A-1", 6000, 2560),
]


class PreferredMonitorTests(unittest.TestCase):
    def test_no_enabled_monitor(self):
        self.assertIsNone(switch.preferred_monitor([]))
        self.assertIsNone(
            switch.preferred_monitor([monitor("DP-2", 0, 2560, disabled=True)])
        )

    def test_single_enabled_monitor(self):
        self.assertEqual(
            switch.preferred_monitor(
                [monitor("HDMI-A-1", 0, 1920), monitor("DP-2", 0, 4000, disabled=True)]
            ),
            "HDMI-A-1",
        )

    def test_runewyrm_desk_uses_the_middle_ultrawide(self):
        self.assertEqual(switch.preferred_monitor(RUNEWYRM), "DP-3")

    def test_center_beats_a_wider_monitor_that_does_not_contain_it(self):
        monitors = [
            monitor("left", 0, 3000),
            monitor("middle", 3000, 2000),
            monitor("right", 5000, 2000),
        ]
        self.assertEqual(switch.preferred_monitor(monitors), "middle")

    def test_gap_uses_the_widest(self):
        monitors = [monitor("left", 0, 1000), monitor("right", 2000, 2000)]
        self.assertEqual(switch.preferred_monitor(monitors), "right")

    def test_overlapping_center_uses_the_wider_one(self):
        monitors = [monitor("narrow", 0, 3000), monitor("wide", 500, 4000)]
        self.assertEqual(switch.preferred_monitor(monitors), "wide")

    def test_equal_pair_split_by_the_seam_uses_the_left_one(self):
        monitors = [monitor("left", 0, 1920), monitor("right", 1920, 1920)]
        self.assertEqual(switch.preferred_monitor(monitors), "left")

    def test_disabled_monitor_is_left_out_of_the_span(self):
        monitors = [
            monitor("left", 0, 1000),
            monitor("gone", 1000, 4000, disabled=True),
            monitor("right", 5000, 1000),
        ]
        self.assertEqual(switch.preferred_monitor(monitors), "left")


class PickCodeWorkspaceTests(unittest.TestCase):
    def test_first_window_gets_code_1(self):
        clients = [code_window("0x10", "2")]
        self.assertEqual(switch.pick_code_workspace(clients, "0x10"), "code-1")

    def test_occupied_slots_are_skipped(self):
        clients = [
            code_window("0x1", "code-1"),
            code_window("0x2", "code-2"),
            code_window("0x10", "4"),
        ]
        self.assertEqual(switch.pick_code_workspace(clients, "0x10"), "code-3")

    def test_window_already_alone_on_a_code_workspace_stays(self):
        clients = [
            code_window("0x1", "code-1"),
            code_window("0x10", "code-4"),
        ]
        self.assertEqual(switch.pick_code_workspace(clients, "0x10"), "code-4")

    def test_a_shared_code_workspace_does_not_keep_the_newcomer(self):
        clients = [
            code_window("0x1", "code-4"),
            code_window("0x10", "code-4"),
        ]
        self.assertEqual(switch.pick_code_workspace(clients, "0x10"), "code-1")

    def test_full_set_uses_the_least_occupied_then_the_lowest_index(self):
        clients = [code_window("0x10", "9")]
        for index, name in enumerate(switch.CODE_WORKSPACES, start=1):
            clients.append(code_window(f"0x{index}", name))
        clients.append(code_window("0x33", "code-3"))
        self.assertEqual(switch.pick_code_workspace(clients, "0x10"), "code-1")

    def test_floating_and_other_classes_do_not_occupy_a_slot(self):
        clients = [
            code_window("0x1", "code-1", floating=True),
            code_window("0x2", "code-2", **{"class": "kitty", "initialClass": "kitty"}),
            code_window("0x3", "code-3", mapped=False),
            code_window("0x10", "1"),
        ]
        self.assertEqual(switch.pick_code_workspace(clients, "0x10"), "code-1")

    def test_address_prefix_and_case_match(self):
        clients = [code_window("0x0000AB", "code-1"), code_window("0x0010", "2")]
        self.assertEqual(switch.pick_code_workspace(clients, "address:0x10"), "code-2")


class PlanSwitchTests(unittest.TestCase):
    def test_visible_numbered_workspace_only_focuses(self):
        monitors = [
            monitor("DP-2", 0, 2560, activeWorkspace={"id": 2, "name": "2"}),
            monitor("DP-3", 2560, 3440, activeWorkspace={"id": 3, "name": "3"}),
        ]
        actions = switch.plan_switch(
            "2",
            monitors,
            {"prefer": False, "cursor_monitor": "DP-3"},
        )
        self.assertEqual(actions, [("focus", "2", "")])

    def test_hidden_numbered_workspace_follows_the_cursor(self):
        monitors = [monitor("DP-2", 0, 2560, activeWorkspace={"id": 1, "name": "1"})]
        actions = switch.plan_switch(
            "4",
            monitors,
            {"prefer": False, "cursor_monitor": "DP-2"},
        )
        self.assertEqual(
            actions,
            [("move_workspace", "4", "DP-2"), ("focus", "4", "")],
        )

    def test_prefer_moves_a_workspace_that_is_visible_on_another_monitor(self):
        monitors = [
            monitor("DP-2", 0, 2560, activeWorkspace={"id": 11, "name": "code-1"}),
            monitor("DP-3", 2560, 3440, activeWorkspace={"id": 3, "name": "3"}),
            monitor("HDMI-A-1", 6000, 2560, activeWorkspace={"id": 4, "name": "4"}),
        ]
        actions = switch.plan_switch("code-1", monitors, {"prefer": True})
        self.assertEqual(
            actions,
            [
                ("move_workspace", "name:code-1", "DP-3"),
                ("focus", "name:code-1", ""),
            ],
        )

    def test_prefer_focuses_when_the_workspace_is_already_on_the_center(self):
        monitors = [
            monitor("DP-2", 0, 2560, activeWorkspace={"id": 1, "name": "1"}),
            monitor("DP-3", 2560, 3440, activeWorkspace={"id": 12, "name": "code-2"}),
        ]
        actions = switch.plan_switch("name:code-2", monitors, {"prefer": True})
        self.assertEqual(actions, [("focus", "name:code-2", "")])

    def test_send_moves_the_window_before_focus(self):
        monitors = [monitor("DP-3", 0, 3440, activeWorkspace={"id": 1, "name": "1"})]
        actions = switch.plan_switch(
            "code-1",
            monitors,
            {
                "prefer": True,
                "window_address": "0x10",
                "window_workspace": "1",
            },
        )
        self.assertEqual(
            actions,
            [
                ("move_workspace", "name:code-1", "DP-3"),
                ("move_window", "name:code-1", "0x10"),
                ("focus", "name:code-1", ""),
            ],
        )

    def test_missing_named_workspace_is_created_on_the_preferred_monitor(self):
        monitors = [
            monitor("DP-2", 0, 2560, activeWorkspace={"id": 1, "name": "1"}),
            monitor("DP-3", 2560, 3440, activeWorkspace={"id": 5, "name": "5"}),
            monitor("HDMI-A-1", 6000, 2560, activeWorkspace={"id": 3, "name": "3"}),
        ]
        actions = switch.plan_switch(
            "code-2",
            monitors,
            {
                "prefer": True,
                "exists": False,
                "window_address": "0x10",
                "window_workspace": "2",
            },
        )
        self.assertEqual(
            actions,
            [
                ("focus_monitor", "", "DP-3"),
                ("focus", "name:code-2", ""),
                ("move_window", "name:code-2", "0x10"),
                ("focus", "name:code-2", ""),
            ],
        )

    def test_send_skips_the_window_move_when_it_is_already_there(self):
        monitors = [monitor("DP-3", 0, 3440, activeWorkspace={"id": 1, "name": "1"})]
        actions = switch.plan_switch(
            "code-3",
            monitors,
            {
                "prefer": True,
                "window_address": "0x10",
                "window_workspace": "code-3",
            },
        )
        self.assertEqual(
            actions,
            [("move_workspace", "name:code-3", "DP-3"), ("focus", "name:code-3", "")],
        )


class PlanPlaceCodeTests(unittest.TestCase):
    def test_places_a_new_code_window_on_the_first_free_workspace(self):
        clients = [
            code_window("0x1", "code-1"),
            code_window("0x10", "2"),
        ]
        actions = switch.plan_place_code(clients, RUNEWYRM, "0x10", [])
        self.assertEqual(
            actions,
            [
                ("focus_monitor", "", "DP-3"),
                ("focus", "name:code-2", ""),
                ("move_window", "name:code-2", "0x10"),
                ("focus", "name:code-2", ""),
            ],
        )

    def test_hidden_existing_code_workspace_is_moved_to_the_center(self):
        clients = [code_window("0x10", "2")]
        workspaces = [{"id": -1, "name": "code-1"}]
        actions = switch.plan_place_code(clients, RUNEWYRM, "0x10", workspaces)
        self.assertEqual(
            actions,
            [
                ("move_workspace", "name:code-1", "DP-3"),
                ("move_window", "name:code-1", "0x10"),
                ("focus", "name:code-1", ""),
            ],
        )

    def test_ignores_a_floating_code_window(self):
        clients = [code_window("0x10", "2", floating=True)]
        self.assertEqual(switch.plan_place_code(clients, RUNEWYRM, "0x10", []), [])

    def test_ignores_an_unknown_address(self):
        self.assertEqual(switch.plan_place_code([], RUNEWYRM, "0x99", []), [])


class ParseArgsTests(unittest.TestCase):
    def test_numbered_workspace_stays_a_plain_switch(self):
        self.assertEqual(
            switch.parse_args(["switch-workspace.py", "2"]),
            {"workspace": "2", "prefer": False, "send": None},
        )

    def test_prefer_and_send_address(self):
        self.assertEqual(
            switch.parse_args(
                ["switch-workspace.py", "code-1", "--prefer", "--send", "0x10"]
            ),
            {"workspace": "code-1", "prefer": True, "send": "0x10"},
        )

    def test_send_without_an_address_means_the_active_window(self):
        self.assertEqual(
            switch.parse_args(["switch-workspace.py", "code-4", "--send", "--prefer"]),
            {"workspace": "code-4", "prefer": True, "send": ""},
        )

    def test_place_code(self):
        self.assertEqual(
            switch.parse_args(["switch-workspace.py", "--place-code", "0x10"]),
            {"place_code": "0x10"},
        )

    def test_help_exits(self):
        with self.assertRaises(SystemExit):
            switch.parse_args(["switch-workspace.py", "--help"])


if __name__ == "__main__":
    unittest.main()
