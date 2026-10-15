from datetime import datetime
from agent.executor import ExecutionContext, LocalToolExecutor, ToolExecutor
from agent.storage import Store
from agent.tools import MockTools, ToolRegistry

NOW = datetime.fromisoformat("2026-10-15T08:00:00+08:00")
LOCATION = {"latitude": 31.23, "longitude": 121.47, "coordinate_system": "wgs84"}
PERIOD = {"start": "2026-10-15T00:00:00+08:00", "end": "2026-10-16T00:00:00+08:00"}
ARGS = {
    "weather.forecast": {"location": LOCATION, "date": "2026-10-15"},
    "health.summary": {"period": PERIOD}, "calendar.events": {"period": PERIOD},
    "maps.search": {"query": "公园", "location": LOCATION, "radius_m": 2000},
    "maps.navigate": {"place_id": "mock-park-1", "mode": "walking"},
    "reminders.create": {"title": "测试", "due_at": "2026-10-16T09:00:00+08:00",
                         "timezone": "Asia/Shanghai", "idempotency_key": "test-reminder"},
}


def setup(**kwargs):
    store = Store()
    adapter = MockTools(store, **kwargs)
    registry = ToolRegistry(LocalToolExecutor(adapter))
    return store, ToolExecutor(registry, store), ExecutionContext(NOW)


def call(name, arguments=None):
    return {"id": name, "name": name, "arguments": ARGS[name] if arguments is None else arguments}
