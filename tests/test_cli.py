import json
from pathlib import Path
import subprocess
import sys
import unittest

from agent.contracts import ROOT, validate


def run_cli(*arguments):
    process = subprocess.run([sys.executable, "-m", "agent", *arguments], cwd=ROOT,
                             capture_output=True, encoding="utf-8")
    return process.returncode, json.loads(process.stdout)


class CLITests(unittest.TestCase):
    def test_acceptance_on_windows_command_line(self):
        code, output = run_cli("ask", "帮我看看今天适不适合跑步，并且导航到附近的公园。", "--store", ":memory:")
        self.assertEqual(code, 0)
        validate("agent-response", output)
        self.assertEqual(output["status"], "pending_confirmation")
        self.assertEqual(len(output["tool_results"]), 4)

    def test_ambiguity_and_mock_fallback(self):
        _, output = run_cli("ask", "导航到公园", "--mock-ambiguous", "--store", ":memory:")
        self.assertEqual(output["status"], "needs_selection")
        self.assertEqual(output["actions"], [])
        _, output = run_cli("ask", "导航到公园", "--mock-no-amap", "--store", ":memory:")
        self.assertEqual(output["actions"][0]["provider"], "apple_maps")

    def test_each_event_outputs_portable_report(self):
        for event in ("alarm.stopped", "location.left_home", "health.workout_completed", "schedule.evening"):
            code, output = run_cli("event", "--type", event, "--workout-id", "mock-workout-1", "--store", ":memory:")
            self.assertEqual(code, 0, output)
            validate("workflow-report", output)

    def test_live_mode_requires_location_and_cli_denial_is_nonzero(self):
        code, output = run_cli("ask", "今天适合跑步吗", "--public-api", "--store", ":memory:")
        self.assertEqual(code, 1)
        self.assertEqual(output["error"]["code"], "location_required")
        code, output = run_cli("ask", "今天适合跑步吗", "--deny", "health.read", "--store", ":memory:")
        self.assertEqual(code, 1)

    def test_noninteractive_confirmation_cancels_mock_write(self):
        code, output = run_cli("ask", "明天早上9点提醒我开会", "--confirm", "--store", ":memory:")
        self.assertEqual(code, 0)
        self.assertEqual(output["status"], "cancelled")
