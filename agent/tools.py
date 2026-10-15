from copy import deepcopy
from datetime import datetime, timedelta
from urllib.parse import urlencode

from .contracts import TOOL_NAMES


class ToolFailure(Exception):
    def __init__(self, code, message, retryable=False):
        self.code, self.message, self.retryable = code, message, retryable
        super().__init__(code)


class MockTools:
    """Explicit synthetic fixtures; never imply Windows reads iPhone data."""
    source = "mock_ios"
    is_mock = True

    def __init__(self, store, *, empty_health=False, ambiguous=False, amap_installed=True,
                 rain=15):
        self.store = store
        self.empty_health = empty_health
        self.ambiguous = ambiguous
        self.amap_installed = amap_installed
        self.rain = rain

    def execute(self, name, args, context):
        if name == "weather.forecast":
            return {"date": args["date"], "temperature_c": 21.0,
                    "precipitation_probability": self.rain, "wind_kph": 8.0,
                    "condition": "演示：多云", "coverage": "daytime"}
        if name == "health.summary":
            end = datetime.fromisoformat(args["period"]["end"])
            workout_end = min(context.now, end - timedelta(seconds=1))
            return {"period": args["period"], "steps": None if self.empty_health else 4200,
                    "sleep_hours": None if self.empty_health else 7.3,
                    "workout_minutes": None if self.empty_health else 25.0,
                    "workouts": [] if self.empty_health else [{"id": "mock-workout-1", "duration_minutes": 25.0,
                                                               "distance_m": 3500.0, "ended_at": workout_end.isoformat()}],
                    "availability": "unknown" if self.empty_health else "available",
                    "missing_reason": "无可用记录；可能未授权或尚未同步" if self.empty_health else None}
        if name == "calendar.events":
            start = datetime.fromisoformat(args["period"]["start"])
            candidate = start.replace(hour=10, minute=0, second=0)
            end = datetime.fromisoformat(args["period"]["end"])
            events = [] if not start <= candidate < end else [{"id": "mock-event-1", "title": "演示日程",
                "start": candidate.isoformat(), "end": (candidate + timedelta(hours=1)).isoformat()}]
            return {"period": args["period"], "events": events}
        if name == "maps.search":
            # Synthetic coordinates near the explicitly supplied test origin, not a real POI lookup.
            location = deepcopy(args["location"])
            places = [{"id": "mock-park-1", "name": "演示公园（非真实搜索）", "location": location,
                       "address": "Mock 地点，仅用于契约测试", "distance_m": 500.0}]
            if self.ambiguous:
                places.append({**deepcopy(places[0]), "id": "mock-park-2", "name": "另一处演示公园", "distance_m": 800.0})
            return {"candidates": places}
        if name == "maps.navigate":
            return navigation_action(args, context, self.amap_installed)
        if name == "reminders.create":
            return self.store.reminder(args, context.now.isoformat())
        raise ToolFailure("unknown_tool", "未注册工具")


def navigation_action(args, context, amap_installed=None):
    place = context.places.get(args["place_id"])
    if place is None:
        raise ToolFailure("unresolved_place", "目的地必须来自本轮 maps.search，禁止猜坐标")
    if len(context.places) > 1 and context.selected_place_id != args["place_id"]:
        raise ToolFailure("ambiguous_place", "多个候选地点；需要用户通过 --place-id 明确选择")
    location = place["location"]
    mode = args["mode"]
    params = {"sourceApplication": "东少", "dlat": location["latitude"],
              "dlon": location["longitude"], "dname": place["name"],
              "dev": 0 if location["coordinate_system"] == "gcj02" else 1,
              "t": {"driving": 0, "transit": 1, "walking": 2, "cycling": 3}[mode], "m": 0}
    if place["id"].startswith("amap-"):
        params["did"] = place["id"][5:]
    amap_uri = "iosamap://path?" + urlencode(params)
    # Apple's link interprets coordinates differently. For GCJ-02, fall back to a name search
    # instead of silently passing incompatible coordinates to a WGS-84 consumer.
    apple = {"daddr": f"{location['latitude']},{location['longitude']}"
             if location["coordinate_system"] == "wgs84" else place["name"],
             "dirflg": {"walking": "w", "driving": "d", "transit": "r", "cycling": "w"}[mode]}
    fallback = "https://maps.apple.com/?" + urlencode(apple)
    return {"action": {"type": "open_navigation", "provider": "apple_maps" if amap_installed is False else "amap",
            "uri": fallback if amap_installed is False else amap_uri, "fallback_uri": fallback,
            "destination": place["name"], "place_id": args["place_id"],
            "coordinate_system": location["coordinate_system"], "requires_confirmation": True,
            "opened": False, "mode": mode, "execution": "proposal"}}


class ToolRegistry:
    def __init__(self, local_executor):
        self.backends = {name: local_executor for name in TOOL_NAMES}

    def register(self, name, executor):
        if name not in TOOL_NAMES:
            raise ValueError("Define and version the JSON contract before registering a tool")
        self.backends[name] = executor

    def get(self, name):
        if name not in self.backends:
            raise ToolFailure("unknown_tool", "未注册工具")
        return self.backends[name]
