"""生成可独立分发的 Draft 2020-12 契约。运行时仅读取 schemas/*.json。"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "schemas"
HEADER = {"$schema": "https://json-schema.org/draft/2020-12/schema"}


def obj(properties, required=None):
    return {"type": "object", "properties": properties,
            "required": list(properties) if required is None else required,
            "additionalProperties": False}


def string(**kw):
    return {"type": "string", **kw}


def number(**kw):
    return {"type": "number", **kw}


def array(items):
    return {"type": "array", "items": items, "maxItems": 100}


def save(name, schema):
    ROOT.mkdir(exist_ok=True)
    (ROOT / f"{name}.json").write_text(
        json.dumps({**HEADER, "$id": f"urn:dongshao:v1:{name}", **schema},
                   ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    location = obj({"latitude": number(minimum=-90, maximum=90),
                    "longitude": number(minimum=-180, maximum=180),
                    "coordinate_system": string(enum=["wgs84", "gcj02"])})
    period = obj({"start": string(format="date-time"), "end": string(format="date-time")})
    date = string(format="date")
    nullable_num = {"type": ["number", "null"], "minimum": 0}
    tools = {
        "weather.forecast": (
            obj({"location": location, "date": date}),
            obj({"date": date, "temperature_c": number(),
                 "precipitation_probability": number(minimum=0, maximum=100),
                 "wind_kph": number(minimum=0), "condition": string(),
                 "coverage": string(enum=["daytime", "full_day"]),
                 "cache_status": string(enum=["fresh", "cached", "stale"])},
                required=["date", "temperature_c", "precipitation_probability", "wind_kph", "condition", "coverage"])),
        "maps.search": (
            obj({"query": string(minLength=1, maxLength=200), "location": location,
                 "radius_m": {"type": "integer", "minimum": 100, "maximum": 50000}}),
            obj({"candidates": array(obj({"id": string(minLength=1), "name": string(),
                 "location": location, "address": string(), "distance_m": number(minimum=0)}))})),
        "maps.navigate": (
            obj({"place_id": string(minLength=1, maxLength=200),
                 "mode": string(enum=["walking", "driving", "transit", "cycling"])}),
            obj({"action": obj({"type": string(const="open_navigation"),
                 "provider": string(enum=["amap", "apple_maps"]),
                 "uri": string(format="uri"), "fallback_uri": string(format="uri"),
                 "destination": string(), "place_id": string(),
                 "coordinate_system": string(enum=["wgs84", "gcj02"]),
                 "requires_confirmation": {"type": "boolean"},
                 "opened": {"type": "boolean"}, "mode": string(),
                 "execution": string(enum=["proposal", "approved_not_opened", "opened"])})})),
        "health.summary": (
            obj({"period": period}),
            obj({"period": period, "steps": {"type": ["integer", "null"], "minimum": 0},
                 "sleep_hours": nullable_num, "workout_minutes": nullable_num,
                 "workouts": array(obj({"id": string(), "duration_minutes": number(minimum=0),
                     "distance_m": {"type": ["number", "null"], "minimum": 0},
                     "ended_at": string(format="date-time")})),
                 "availability": string(enum=["available", "partial", "unknown"]),
                 "missing_reason": {"type": ["string", "null"]}})),
        "calendar.events": (
            obj({"period": period}),
            obj({"period": period, "events": array(obj({"id": string(), "title": string(),
                 "start": string(format="date-time"), "end": string(format="date-time")}))})),
        "reminders.create": (
            obj({"title": string(minLength=1, maxLength=300),
                 "due_at": string(format="date-time"), "timezone": string(minLength=1),
                 "idempotency_key": string(minLength=1, maxLength=200)}),
            obj({"id": string(), "title": string(), "due_at": string(format="date-time"),
                 "timezone": string(), "simulated": {"type": "boolean"}})),
    }
    for name, (inputs, outputs) in tools.items():
        save(name, {"title": name, "$ref": "#/$defs/input",
                    "$defs": {"input": inputs, "output": outputs}})
    save("tool-call", obj({"id": string(minLength=1, maxLength=100),
         "name": string(minLength=3, maxLength=100), "arguments": {"type": "object"}}))
    save("tool-result", obj({"contract_version": string(const="1.0"), "trace_id": string(),
         "call_id": string(), "tool": string(minLength=3, maxLength=100),
         "status": string(enum=["ok", "pending_confirmation", "needs_selection", "denied",
                                 "cancelled", "error", "unavailable"]),
         "data": {"type": "object"},
         "error": {"type": ["object", "null"], "properties": {
             "code": string(), "message": string(), "retryable": {"type": "boolean"}},
             "required": ["code", "message", "retryable"], "additionalProperties": False},
         "source": string(), "is_mock": {"type": "boolean"},
         "collected_at": string(format="date-time")}))
    save("system-event", obj({"contract_version": string(const="1.0"),
         "id": string(minLength=1, maxLength=200),
         "type": string(enum=["alarm.stopped", "location.left_home", "health.workout_completed", "schedule.evening"]),
         "occurred_at": string(format="date-time"), "received_at": string(format="date-time"),
         "payload": obj({"workout_id": string(minLength=1, maxLength=200)}, required=[])},
         required=["contract_version", "id", "type", "occurred_at", "received_at", "payload"]))
    policy = {
        "weather.forecast": ("readOnly", ["location.share"]),
        "maps.search": ("readOnly", ["location.share"]),
        "maps.navigate": ("externalAction", []),
        "health.summary": ("readOnly", ["health.read"]),
        "calendar.events": ("readOnly", ["calendar.read"]),
        "reminders.create": ("localWrite", ["reminders.write"]),
    }
    save("permission-policy", obj({"contract_version": string(const="1.0"),
         "tools": obj({name: obj({"risk": string(enum=["readOnly", "localWrite", "externalAction", "sensitive"]),
             "scopes": array(string()), "confirmation": {"type": "boolean"}}) for name in tools})}))
    defaults = {"contract_version": "1.0", "tools": {name: {
        "risk": risk, "scopes": scopes, "confirmation": risk != "readOnly"}
        for name, (risk, scopes) in policy.items()}}
    config = ROOT.parent / "config"
    config.mkdir(exist_ok=True)
    if not (config / "permissions.json").exists():
        (config / "permissions.json").write_text(json.dumps(defaults, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result_schema = json.loads((ROOT / "tool-result.json").read_text(encoding="utf-8"))
    result_schema.pop("$id")
    result_schema.pop("$schema")
    assessment = {"type": ["object", "null"], "properties": {
        "recommendation": string(enum=["insufficient_data", "caution", "limited_data", "consider_easy_run"]),
        "reasons": array(string()), "scope": string()},
        "required": ["recommendation", "reasons", "scope"], "additionalProperties": False}
    save("agent-response", obj({"contract_version": string(const="1.0"), "app": string(const="东少"),
         "trace_id": string(), "planner": string(),
         "status": string(enum=["completed", "pending_confirmation", "needs_selection", "cancelled", "error"]),
         "message": string(), "assessment": assessment, "tool_results": array(result_schema),
         "actions": array(tools["maps.navigate"][1]["properties"]["action"]),
         "contains_mock_data": {"type": "boolean"}}))
    save("workflow-report", obj({"contract_version": string(const="1.0"),
         "report_id": string(), "workflow": string(enum=["morning_brief", "leaving_home", "workout_analysis", "daily_review"]),
         "status": string(enum=["completed", "duplicate", "retry_pending", "failed"]),
         "trace_id": string(), "created_at": string(format="date-time"), "summary": string(),
         "tool_results": array(result_schema), "assessment": assessment,
         "notification": obj({"should_notify": {"type": "boolean"}, "reason": string(), "delivered": {"type": "boolean"}}),
         "contains_mock_data": {"type": "boolean"}}))
    save("automation-policy", obj({"contract_version": string(const="1.0"),
        "timezone": string(const="Asia/Shanghai"),
        "quiet_start": {"type": "integer", "minimum": 0, "maximum": 23},
        "quiet_end": {"type": "integer", "minimum": 0, "maximum": 23},
        "cooldown_minutes": {"type": "integer", "minimum": 1, "maximum": 1440},
        "max_event_attempts": {"type": "integer", "minimum": 1, "maximum": 10},
        "stale_event_hours": number(minimum=0, maximum=168),
        "rain_threshold": number(minimum=0, maximum=100),
        "wind_threshold_kph": number(minimum=0),
        "running_min_c": number(), "running_max_c": number(),
        "minimum_sleep_hours": number(minimum=0, maximum=24)}))
    manifest_tool = obj({"name": string(minLength=3, maxLength=100),
        "input_schema": string(), "output_schema": string(),
        "risk": string(enum=["readOnly", "localWrite", "externalAction", "sensitive"]),
        "permissions": array(string()), "requires_foreground": {"type": "boolean"},
        "requires_network": {"type": "boolean"}, "requires_confirmation": {"type": "boolean"},
        "supported_os": obj({"ios": string()}), "fallback": {"type": ["string", "null"]},
        "timeout": number(minimum=0.01, maximum=120), "idempotency_key": {"type": ["string", "null"]}})
    save("tool-manifest", {"$defs": {"tool": manifest_tool}, **obj({
        "contract_version": string(const="1.0"), "tools": array(manifest_tool)})})
    entries = []
    for name, (risk, scopes) in policy.items():
        entries.append({"name": name, "input_schema": f"urn:dongshao:v1:{name}#/$defs/input",
            "output_schema": f"urn:dongshao:v1:{name}#/$defs/output", "risk": risk,
            "permissions": scopes, "requires_foreground": name == "maps.navigate",
            "requires_network": name in ("weather.forecast", "maps.search"),
            "requires_confirmation": risk != "readOnly", "supported_os": {"ios": "17.0"},
            "fallback": {"weather.forecast": "marked_cached_forecast", "maps.navigate": "apple_maps"}.get(name),
            "timeout": 20, "idempotency_key": "idempotency_key" if name == "reminders.create" else None})
    contracts = ROOT.parent / "contracts"
    contracts.mkdir(exist_ok=True)
    (contracts / "tool-manifest.json").write_text(json.dumps({"contract_version": "1.0", "tools": entries},
        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
