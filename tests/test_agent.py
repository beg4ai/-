import os
import unittest
from unittest.mock import patch

from agent.coordinator import AgentCoordinator
from agent.planning import OllamaProvider, RulesProvider, Turn, tool_definitions
from agent.tools import ToolFailure
from tests.helpers import ARGS, LOCATION, call, setup


class ScriptedProvider:
    name = "test_model"

    def __init__(self, turns):
        self.turns = iter(turns)
        self.messages = []

    def next_turn(self, messages, tools):
        self.messages = list(messages)
        return next(self.turns)


class AgentTests(unittest.TestCase):
    def test_acceptance_sentence_routes_four_tools(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        result = AgentCoordinator(executor, RulesProvider(ctx.now, LOCATION)).run(
            "帮我看看今天适不适合跑步，并且导航到附近的公园。", ctx, LOCATION)
        self.assertEqual([r["tool"] for r in result["tool_results"]],
                         ["weather.forecast", "health.summary", "maps.search", "maps.navigate"])
        self.assertEqual(result["status"], "pending_confirmation")
        self.assertTrue(result["actions"][0]["uri"].startswith("iosamap://path?"))
        self.assertFalse(result["actions"][0]["opened"])
        self.assertIsNotNone(result["assessment"])

    def test_model_multiturn_and_private_data_redaction(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        provider = ScriptedProvider([Turn([call("health.summary")]), Turn([], "完成")])
        result = AgentCoordinator(executor, provider).run("运动分析", ctx, LOCATION)
        self.assertEqual(result["tool_results"][0]["status"], "ok")
        tool_message = next(m for m in provider.messages if m["role"] == "tool")
        self.assertIn('"redacted": true', tool_message["content"])
        self.assertNotIn("sleep_hours", tool_message["content"])

    def test_untrusted_model_cannot_approve(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        provider = ScriptedProvider([Turn([call("reminders.create")])])
        self.assertEqual(AgentCoordinator(executor, provider).run("提醒", ctx, LOCATION)["status"], "pending_confirmation")
        self.assertEqual(store.db.execute("SELECT count(*) FROM reminders").fetchone()[0], 0)

    def test_model_loop_is_bounded(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        provider = ScriptedProvider([Turn([call("weather.forecast")])] * 5)
        with self.assertRaises(ToolFailure) as raised:
            AgentCoordinator(executor, provider).run("天气", ctx, LOCATION)
        self.assertEqual(raised.exception.code, "repeated_tool_call")

    def test_invalid_model_response_and_aliases(self):
        from tests.test_adapters import FakeHTTP
        with patch.dict(os.environ, {"AGENT_LLM_MODEL": "configured-model"}):
            provider = OllamaProvider(FakeHTTP({"message": {"tool_calls": [{"function": {
                "name": "shell__run", "arguments": {}}}]}}))
        with self.assertRaises(ToolFailure):
            provider.next_turn([], tool_definitions())
        self.assertEqual(tool_definitions()[0]["function"]["name"], "weather__forecast")

    def test_ollama_wire_format_normalizes_tool_calls(self):
        from tests.test_adapters import FakeHTTP
        http = FakeHTTP({"message": {"role": "assistant", "content": "", "tool_calls": [{"function": {
            "name": "weather__forecast", "arguments": ARGS["weather.forecast"]}}]}})
        with patch.dict(os.environ, {"AGENT_LLM_MODEL": "configured-model"}):
            provider = OllamaProvider(http)
        self.assertEqual(provider.next_turn([], tool_definitions()).calls[0]["name"], "weather.forecast")

    def test_empty_health_is_limited_and_bad_weather_is_cautious(self):
        store, executor, ctx = setup(empty_health=True, rain=80)
        self.addCleanup(store.close)
        result = AgentCoordinator(executor, RulesProvider(ctx.now, LOCATION)).run("今天适合跑步吗", ctx, LOCATION)
        self.assertEqual(result["assessment"]["recommendation"], "caution")
        self.assertIn("健康记录缺失", " ".join(result["assessment"]["reasons"]))

    def test_offline_unknown_intent_does_not_run_tools(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        result = AgentCoordinator(executor, RulesProvider(ctx.now, LOCATION)).run("读取微信通知", ctx, LOCATION)
        self.assertEqual(result["tool_results"], [])
