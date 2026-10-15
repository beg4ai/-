import json
from pathlib import Path
import unittest
from uuid import uuid4

from agent.contracts import ROOT
from agent.rules import load_rules
from agent.storage import Store
from agent.automation import AutomationEngine
from agent.executor import ToolExecutor, LocalToolExecutor, ExecutionContext
from agent.tools import MockTools, ToolRegistry
from tests.helpers import call, setup, LOCATION, NOW
from tests.test_automation import event


class PortabilityTests(unittest.TestCase):
    def test_shared_swift_contract_vectors(self):
        cases = json.loads((ROOT / "fixtures/tool-cases.json").read_text(encoding="utf-8"))
        for case in cases:
            with self.subTest(case=case["case"]):
                store, executor, ctx = setup(**case.get("mock_options", {}))
                try:
                    ctx.permissions.difference_update(case.get("deny", []))
                    if case.get("search_first"):
                        executor.execute(call("maps.search"), ctx)
                    confirm = (lambda *_: case["confirm"]) if "confirm" in case else None
                    result = executor.execute(call(case["tool"], case["arguments"]), ctx, confirm)
                    self.assertEqual(result["status"], case["status"])
                    for key, value in case["subset"].items():
                        self.assertEqual(result["data"][key], value)
                finally:
                    store.close()

    def test_persistent_deduplication_after_reopen(self):
        path = ROOT / ".tmp" / f"state-{uuid4()}.sqlite3"
        path.parent.mkdir(exist_ok=True)
        self.addCleanup(lambda: [p.unlink(missing_ok=True) for p in (path, Path(str(path) + "-wal"), Path(str(path) + "-shm"))])
        for index in range(2):
            store = Store(path)
            try:
                executor = ToolExecutor(ToolRegistry(LocalToolExecutor(MockTools(store))), store)
                ctx = ExecutionContext(NOW)
                report = AutomationEngine(executor, store).process(event(ctx), ctx, LOCATION)
                self.assertEqual(report["status"], "completed" if index == 0 else "duplicate")
            finally:
                store.close()

    def test_missing_workout_waits_for_sync(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        engine = AutomationEngine(executor, store)
        report = engine.process(event(ctx, "health.workout_completed", workout_id="not-synced"), ctx, LOCATION)
        self.assertEqual(report["status"], "retry_pending")
        self.assertEqual(len(engine.replay(ctx, LOCATION)), 1)
        self.assertEqual(len(engine.replay(ctx, LOCATION)), 1)
        self.assertEqual(engine.replay(ctx, LOCATION), [])

    def test_rules_are_configurable(self):
        store, executor, ctx = setup(rain=40)
        self.addCleanup(store.close)
        rules = {**load_rules(), "rain_threshold": 30}
        report = AutomationEngine(executor, store, rules=rules).process(event(ctx, "location.left_home"), ctx, LOCATION)
        self.assertTrue(report["notification"]["should_notify"])

    def test_policy_cannot_downgrade_external_actions(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        executor.policy.document["tools"]["maps.navigate"].update(risk="readOnly", confirmation=False)
        executor.execute(call("maps.search"), ctx)
        self.assertEqual(executor.execute(call("maps.navigate"), ctx)["status"], "pending_confirmation")
