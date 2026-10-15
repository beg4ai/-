import unittest

from jsonschema import Draft202012Validator
from agent.contracts import ContractError, ROOT, TOOL_NAMES, schema, validate
import json


class ContractTests(unittest.TestCase):
    def test_all_schemas_are_valid(self):
        for path in (ROOT / "schemas").glob("*.json"):
            Draft202012Validator.check_schema(json.loads(path.read_text(encoding="utf-8")))
        self.assertEqual(len(TOOL_NAMES), 6)

    def test_policy_is_portable(self):
        validate("permission-policy", json.loads((ROOT / "config/permissions.json").read_text(encoding="utf-8")))

    def test_reject_extra_fields_and_bad_dates(self):
        for args in ({"title": "测试", "due_at": "tomorrow", "timezone": "Asia/Shanghai", "idempotency_key": "a"},
                     {"place_id": "a", "mode": "walking", "approved": True}):
            with self.assertRaises(ContractError):
                validate("reminders.create" if "title" in args else "maps.navigate", args, "input")

    def test_reject_non_finite(self):
        with self.assertRaises(ContractError):
            validate("maps.search", {"query": "公园", "location": {"latitude": float("nan"),
                     "longitude": 121, "coordinate_system": "wgs84"}, "radius_m": 2000}, "input")

    def test_native_results_can_use_same_contract_without_mock_flags(self):
        validate("reminders.create", {"id": "native-id", "title": "会议",
            "due_at": "2026-10-16T09:00:00+08:00", "timezone": "Asia/Shanghai", "simulated": False}, "output")
