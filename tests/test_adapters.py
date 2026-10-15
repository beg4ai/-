from datetime import datetime
import os
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

from agent.adapters import AmapSearch, OpenMeteo
from agent.executor import RemoteToolExecutor
from agent.http import JSONHTTP
from agent.tools import ToolFailure
from tests.helpers import ARGS, call, setup


class FakeHTTP:
    def __init__(self, *responses):
        self.responses = iter(responses)
        self.urls = []

    def request(self, url, **kwargs):
        self.urls.append(url)
        value = next(self.responses)
        if isinstance(value, Exception):
            raise value
        return value


class AdapterTests(unittest.TestCase):
    def test_weather_normalizes_real_protocol_fixture(self):
        hourly = {"time": [f"2026-10-15T{h:02d}:00" for h in range(24)],
                  "temperature_2m": [20] * 24, "precipitation_probability": [10] * 24,
                  "wind_speed_10m": [8] * 24, "weather_code": [1] * 24}
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        http = FakeHTTP({"hourly": hourly})
        executor.registry.register("weather.forecast", RemoteToolExecutor(OpenMeteo(http)))
        result = executor.execute(call("weather.forecast"), ctx)
        self.assertEqual(result["data"]["temperature_c"], 20)
        self.assertFalse(result["is_mock"])
        self.assertEqual(parse_qs(urlsplit(http.urls[0]).query)["wind_speed_unit"], ["kmh"])

    def test_amap_coordinate_conversion_and_result(self):
        http = FakeHTTP({"status": "1", "locations": "121.47,31.23"},
                        {"status": "1", "pois": [{"id": "B1", "name": "真实协议测试公园",
                           "location": "121.48,31.24", "address": "测试地址", "distance": "300"}]})
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        executor.registry.register("maps.search", RemoteToolExecutor(AmapSearch(http)))
        with patch.dict(os.environ, {"AMAP_API_KEY": "test-only-not-real"}):
            result = executor.execute(call("maps.search"), ctx)
        self.assertEqual(result["status"], "ok", result)
        self.assertEqual(result["data"]["candidates"][0]["location"]["coordinate_system"], "gcj02")
        action = executor.execute(call("maps.navigate", {"place_id": "amap-B1", "mode": "walking"}), ctx)["data"]["action"]
        self.assertEqual(parse_qs(urlsplit(action["uri"]).query)["dev"], ["0"])
        self.assertEqual(parse_qs(urlsplit(action["fallback_uri"]).query)["daddr"], ["真实协议测试公园"])

    def test_network_failure_is_structured_and_redacted(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        executor.registry.register("weather.forecast", RemoteToolExecutor(OpenMeteo(FakeHTTP(
            ToolFailure("network_unavailable", "网络不可用", True)))))
        result = executor.execute(call("weather.forecast"), ctx)
        self.assertTrue(result["error"]["retryable"])

    def test_missing_key_and_malformed_responses(self):
        store, executor, ctx = setup()
        self.addCleanup(store.close)
        executor.registry.register("maps.search", RemoteToolExecutor(AmapSearch(FakeHTTP())))
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(executor.execute(call("maps.search"), ctx)["error"]["code"], "missing_api_key")
        executor.registry.register("weather.forecast", RemoteToolExecutor(OpenMeteo(FakeHTTP({}))))
        self.assertEqual(executor.execute(call("weather.forecast"), ctx)["error"]["code"], "invalid_response")

    def test_insecure_remote_http_disallowed(self):
        with self.assertRaises(ToolFailure):
            JSONHTTP().request("http://example.com/api")
