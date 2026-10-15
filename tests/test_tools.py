import unittest
from agent.contracts import validate
from agent.tools import ToolFailure
from tests.helpers import ARGS, call, setup


class ToolTests(unittest.TestCase):
    def test_every_mock_matches_input_and_output_contract(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        for name in ARGS:
            with self.subTest(tool=name):
                result = executor.execute(call(name), ctx, lambda *_: True)
                self.assertEqual(result["status"], "ok", result)
                self.assertTrue(result["is_mock"])
                validate(name, result["data"], "output")

    def test_permission_denial(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        ctx.permissions.clear()
        for name in ("weather.forecast", "health.summary", "calendar.events", "reminders.create"):
            self.assertEqual(executor.execute(call(name), ctx)["status"], "denied")

    def test_write_requires_confirmation_and_cancel_has_no_effect(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        self.assertEqual(executor.execute(call("reminders.create"), ctx)["status"], "pending_confirmation")
        self.assertEqual(executor.execute(call("reminders.create"), ctx, lambda *_: False)["status"], "cancelled")
        self.assertEqual(store.db.execute("SELECT count(*) FROM reminders").fetchone()[0], 0)

    def test_reminder_idempotency_and_conflict(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        first = executor.execute(call("reminders.create"), ctx, lambda *_: True)
        self.assertEqual(first, executor.execute(call("reminders.create"), ctx, lambda *_: True))
        result = executor.execute(call("reminders.create", {**ARGS["reminders.create"], "title": "changed"}), ctx, lambda *_: True)
        self.assertEqual(result["status"], "error")
        self.assertEqual(store.db.execute("SELECT count(*) FROM reminders").fetchone()[0], 1)

    def test_ambiguity_requires_human_choice(self):
        store, executor, ctx = setup(ambiguous=True)
        self.addCleanup(store.close)
        executor.execute(call("maps.search"), ctx)
        self.assertEqual(executor.execute(call("maps.navigate"), ctx)["status"], "needs_selection")
        ctx.selected_place_id = "mock-park-1"
        self.assertEqual(executor.execute(call("maps.navigate"), ctx)["status"], "pending_confirmation")

    def test_no_amap_falls_back_and_never_opens(self):
        store, executor, ctx = setup(amap_installed=False)
        self.addCleanup(store.close)
        executor.execute(call("maps.search"), ctx)
        action = executor.execute(call("maps.navigate"), ctx)["data"]["action"]
        self.assertEqual(action["provider"], "apple_maps")
        self.assertFalse(action["opened"])

    def test_forged_destination_and_model_approval_rejected(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        self.assertEqual(executor.execute(call("maps.navigate"), ctx)["error"]["code"], "unresolved_place")
        self.assertEqual(executor.execute(call("reminders.create", {**ARGS["reminders.create"], "approved": True}), ctx)["error"]["code"], "schema_invalid")
        with self.assertRaises(ToolFailure):
            executor.execute({"name": "shell.run"}, ctx)

    def test_health_missing_not_zero(self):
        store, executor, ctx = setup(empty_health=True)
        self.addCleanup(store.close)
        data = executor.execute(call("health.summary"), ctx)["data"]
        self.assertIsNone(data["steps"])
        self.assertEqual(data["availability"], "unknown")

    def test_period_and_timezone_checks(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        result = executor.execute(call("reminders.create", {**ARGS["reminders.create"], "timezone": "America/New_York"}), ctx)
        self.assertEqual(result["error"]["code"], "timezone_mismatch")
        result = executor.execute(call("health.summary", {"period": {"start": "2026-10-16T00:00:00+08:00", "end": "2026-10-15T00:00:00+08:00"}}), ctx)
        self.assertEqual(result["error"]["code"], "invalid_period")

    def test_invalid_numeric_parameters_are_audited_without_crash(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        from copy import deepcopy
        arguments = deepcopy(ARGS["weather.forecast"])
        arguments["location"]["latitude"] = float("nan")
        self.assertEqual(executor.execute(call("weather.forecast", arguments), ctx)["error"]["code"], "schema_invalid")
        self.assertEqual(store.db.execute("SELECT count(*) FROM audit").fetchone()[0], 1)
