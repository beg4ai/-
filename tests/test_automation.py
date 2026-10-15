from datetime import timedelta
import unittest

from agent.automation import AutomationEngine
from agent.executor import RemoteToolExecutor
from agent.adapters import OpenMeteo
from agent.tools import ToolFailure
from tests.helpers import LOCATION, setup
from tests.test_adapters import FakeHTTP


def event(ctx, kind="alarm.stopped", id="test-event", **payload):
    return {"contract_version": "1.0", "id": id, "type": kind,
            "occurred_at": ctx.now.isoformat(), "received_at": ctx.now.isoformat(), "payload": payload}


class AutomationTests(unittest.TestCase):
    def test_four_workflows(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        engine = AutomationEngine(executor, store)
        for kind in ("alarm.stopped", "location.left_home", "health.workout_completed", "schedule.evening"):
            with self.subTest(kind=kind):
                report = engine.process(event(ctx, kind, kind, **({"workout_id": "mock-workout-1"} if "workout" in kind else {})), ctx, LOCATION)
                self.assertEqual(report["status"], "completed")
                self.assertFalse(report["notification"]["delivered"])
                self.assertTrue(report["summary"])

    def test_alarm_day_and_workout_uuid_deduplication(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        engine = AutomationEngine(executor, store)
        engine.process(event(ctx), ctx, LOCATION)
        self.assertEqual(engine.process(event(ctx, id="second-alarm"), ctx, LOCATION)["status"], "duplicate")
        engine.process(event(ctx, "health.workout_completed", workout_id="mock-workout-1"), ctx, LOCATION)
        self.assertEqual(engine.process(event(ctx, "health.workout_completed", id="retry", workout_id="mock-workout-1"), ctx, LOCATION)["status"], "duplicate")
        self.assertEqual(store.db.execute("SELECT count(*) FROM reports").fetchone()[0], 2)

    def test_leaving_home_quiet_hours_cooldown_and_same_risk(self):
        store, executor, ctx = setup(rain=80)
        self.addCleanup(store.close)
        engine = AutomationEngine(executor, store)
        first = engine.process(event(ctx, "location.left_home", "away1"), ctx, LOCATION)
        self.assertTrue(first["notification"]["should_notify"])
        ctx.now += timedelta(minutes=20)
        second = engine.process(event(ctx, "location.left_home", "away2"), ctx, LOCATION)
        self.assertEqual(second["notification"]["reason"], "unchanged_risk")
        executor.registry.get("weather.forecast").adapter.rain = 90
        # A genuinely new category within 90 minutes is suppressed by cooldown.
        store.db.execute("UPDATE notification_history SET fingerprint='other'")
        store.db.commit()
        third = engine.process(event(ctx, "location.left_home", "away3"), ctx, LOCATION)
        self.assertEqual(third["notification"]["reason"], "cooldown")
        ctx.now = ctx.now.replace(hour=23)
        quiet = engine.process(event(ctx, "schedule.evening", "night"), ctx, LOCATION)
        self.assertEqual(quiet["notification"]["reason"], "quiet_hours")

    def test_offline_event_persists_and_replays_once(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        engine = AutomationEngine(executor, store)
        mock_backend = executor.registry.get("weather.forecast")
        executor.registry.register("weather.forecast", RemoteToolExecutor(OpenMeteo(FakeHTTP(
            ToolFailure("network_unavailable", "离线", True)))))
        result = engine.process(event(ctx), ctx, LOCATION)
        self.assertEqual(result["status"], "retry_pending")
        self.assertEqual(store.db.execute("SELECT count(*) FROM reports").fetchone()[0], 0)
        executor.registry.register("weather.forecast", mock_backend)
        self.assertEqual(engine.replay(ctx, LOCATION)[0]["status"], "completed")
        self.assertEqual(engine.replay(ctx, LOCATION), [])

    def test_missing_data_and_permissions_do_not_crash(self):
        store, executor, ctx = setup(empty_health=True)
        self.addCleanup(store.close)
        ctx.permissions.discard("calendar.read")
        report = AutomationEngine(executor, store).process(event(ctx), ctx, LOCATION)
        self.assertIn("缺失", report["summary"])
        self.assertIn("日程不可用", report["summary"])

    def test_replay_keeps_event_date_and_suppresses_stale_notification(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        original = event(ctx)
        ctx.now += timedelta(days=1)
        report = AutomationEngine(executor, store).process(original, ctx, LOCATION)
        self.assertEqual(report["tool_results"][0]["data"]["date"], "2026-10-15")
        self.assertEqual(report["notification"]["reason"], "stale_event")

    def test_workout_event_requires_uuid(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        with self.assertRaises(ToolFailure):
            AutomationEngine(executor, store).process(event(ctx, "health.workout_completed"), ctx, LOCATION)
