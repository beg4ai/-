from dataclasses import dataclass, field
from datetime import datetime, timedelta
import json
from uuid import uuid4
from zoneinfo import ZoneInfo

from .contracts import ContractError, ROOT, validate
from .tools import ToolFailure


@dataclass
class ExecutionContext:
    now: datetime
    permissions: set = field(default_factory=lambda: {"location.share", "health.read", "calendar.read", "reminders.write"})
    trace_id: str = field(default_factory=lambda: str(uuid4()))
    places: dict = field(default_factory=dict)
    selected_place_id: str | None = None


class LocalToolExecutor:
    """Windows transport: Mock. Future Swift implements these same input/output schemas."""
    def __init__(self, adapter):
        self.adapter = adapter

    def execute(self, name, arguments, context):
        return self.adapter.execute(name, arguments, context)

    @property
    def source(self):
        return self.adapter.source

    @property
    def is_mock(self):
        return self.adapter.is_mock


class RemoteToolExecutor(LocalToolExecutor):
    """Public API adapters only; not an arbitrary remote/native command proxy."""


class PermissionPolicy:
    def __init__(self):
        self.document = json.loads((ROOT / "config/permissions.json").read_text(encoding="utf-8"))
        validate("permission-policy", self.document)

    def rule(self, name):
        rule = dict(self.document["tools"][name])
        # A model or policy file cannot downgrade an external action's minimum risk.
        if name == "maps.navigate":
            rule.update(risk="externalAction", confirmation=True)
        if name == "reminders.create":
            rule["risk"] = "localWrite"
            # This prototype deliberately has no persistent trust/auto-write feature.
            rule["confirmation"] = True
        if rule["risk"] in {"externalAction", "sensitive"}:
            rule["confirmation"] = True
        return rule


class ToolExecutor:
    def __init__(self, registry, store):
        self.registry, self.store = registry, store
        self.policy = PermissionPolicy()

    def execute(self, call, context, confirm=None):
        """confirm is trusted UI callback; never read approval from model-controlled arguments."""
        name = call.get("name", "") if isinstance(call, dict) else ""
        result = {"contract_version": "1.0", "trace_id": context.trace_id,
                  "call_id": str(call.get("id", "invalid")) if isinstance(call, dict) else "invalid",
                  "tool": name, "status": "error", "data": {}, "error": None,
                  "source": "executor", "is_mock": False, "collected_at": context.now.isoformat()}
        risk = "unknown"
        try:
            # Unknown tool cannot satisfy tool-result's closed enum. Reject at the boundary.
            self.registry.get(name)
            validate("tool-call", call)
            args = call["arguments"]
            validate(name, args, "input")
            rule = self.policy.rule(name)
            risk = rule["risk"]
            if not set(rule["scopes"]).issubset(context.permissions):
                raise ToolFailure("permission_denied", "权限未授予或已撤销；请在系统设置或配置中授权")
            self._semantic_checks(name, args, context)
            backend = self.registry.get(name)
            result.update(source=backend.source, is_mock=backend.is_mock)
            preview = None
            # Navigation adapter is pure: creates a proposal, never opens a URL.
            if name == "maps.navigate":
                preview = backend.execute(name, args, context)
                validate(name, preview, "output")
            if rule["confirmation"]:
                if confirm is None:
                    result.update(status="pending_confirmation", data=preview or {"preview": args})
                    return self._finish(result, call, context, risk)
                if not confirm(name, preview or args):
                    result.update(status="cancelled")
                    return self._finish(result, call, context, risk)
            data = preview if preview is not None else backend.execute(name, args, context)
            validate(name, data, "output")
            if "period" in args and data.get("period") != args["period"]:
                raise ToolFailure("response_mismatch", "返回数据窗口与请求不一致")
            if name == "weather.forecast" and data["date"] != args["date"]:
                raise ToolFailure("response_mismatch", "天气日期与请求不一致")
            if name == "maps.search":
                candidates = data["candidates"]
                ids = [p["id"] for p in candidates]
                if len(ids) != len(set(ids)):
                    raise ToolFailure("invalid_response", "地点 ID 重复")
                context.places = {p["id"]: p for p in candidates}
            if name == "maps.navigate":
                data["action"].update(requires_confirmation=False, execution="approved_not_opened")
            result.update(status="ok", data=data)
        except ContractError:
            result["error"] = {"code": "schema_invalid", "message": "参数或工具返回值不符合契约", "retryable": False}
        except ToolFailure as error:
            result["status"] = {"permission_denied": "denied", "ambiguous_place": "needs_selection",
                                "no_data": "unavailable"}.get(error.code, "error")
            result["error"] = {"code": error.code, "message": error.message, "retryable": error.retryable}
        except (ValueError, TypeError, KeyError):
            result["error"] = {"code": "invalid_response", "message": "适配器数据或时间无效", "retryable": False}
        # Unknown names are an API misuse, not a valid result for a registered tool.
        if name not in self.registry.backends:
            raise ToolFailure("unknown_tool", "未注册工具")
        return self._finish(result, call, context, risk)

    def _finish(self, result, call, context, risk):
        validate("tool-result", result)
        self.store.audit(context.trace_id, result["tool"], risk,
                         call.get("arguments", {}), result["status"],
                         result["error"]["code"] if result["error"] else None, context.now.isoformat())
        return result

    @staticmethod
    def _semantic_checks(name, args, context):
        if "period" in args:
            start = datetime.fromisoformat(args["period"]["start"])
            end = datetime.fromisoformat(args["period"]["end"])
            if not start < end or end - start > timedelta(days=31):
                raise ToolFailure("invalid_period", "查询窗口必须递增且不超过 31 天")
        if name == "maps.search" and not args["query"].strip():
            raise ToolFailure("empty_query", "地点关键词不能为空白")
        if name == "reminders.create":
            if not args["title"].strip():
                raise ToolFailure("empty_title", "提醒标题不能为空白")
            due = datetime.fromisoformat(args["due_at"])
            try:
                zone = ZoneInfo(args["timezone"])
            except (KeyError, ValueError):
                raise ToolFailure("invalid_timezone", "请使用有效 IANA 时区")
            if due.utcoffset() != due.astimezone(zone).utcoffset():
                raise ToolFailure("timezone_mismatch", "日期偏移量与指定时区不一致")
            if due <= context.now:
                raise ToolFailure("past_due", "提醒时间必须晚于当前时间")
