"""Replaceable planning providers. The offline rules provider is not presented as an LLM."""
from dataclasses import dataclass
from datetime import datetime, timedelta
import json
import os
import re
from typing import Protocol

from .contracts import schema, TOOL_NAMES, validate
from .http import JSONHTTP
from .tools import ToolFailure


@dataclass
class Turn:
    calls: list
    content: str = ""
    wire_message: dict | None = None


class LLMProvider(Protocol):
    name: str

    def next_turn(self, messages: list, tools: list) -> Turn: ...


def tool_definitions():
    descriptions = {
        "weather.forecast": "查询指定日期白天天气，运行建议先调用此工具",
        "health.summary": "查询本地授权健康聚合；缺失数据不代表零",
        "calendar.events": "读取授权时间窗口内日程",
        "maps.search": "以用户配置位置搜索候选 POI，返回 ID；多个候选必须让用户选择",
        "maps.navigate": "只生成导航动作；place_id 必须来自本轮搜索；外部打开需要用户确认",
        "reminders.create": "创建提醒，需带时区日期、稳定幂等键和用户确认",
    }
    # Portable aliases: several model providers restrict function names to [a-zA-Z0-9_-].
    return [{"type": "function", "function": {
        "name": name.replace(".", "__"), "description": descriptions[name],
        "parameters": schema(name)["$defs"]["input"]}} for name in TOOL_NAMES]


class OllamaProvider:
    name = "ollama"

    def __init__(self, http=None):
        self.url = os.environ.get("AGENT_LLM_URL", "http://127.0.0.1:11434/api/chat")
        self.model = os.environ.get("AGENT_LLM_MODEL")
        if not self.model:
            raise ToolFailure("missing_model", "请配置 AGENT_LLM_MODEL，选择支持 tool calling 的模型")
        self.http = http or JSONHTTP(timeout=45, retries=0)

    def next_turn(self, messages, tools):
        key = os.environ.get("AGENT_LLM_API_KEY")
        payload = self.http.request(self.url, body={"model": self.model, "messages": messages,
                                    "tools": tools, "stream": False},
                                    headers={"Authorization": f"Bearer {key}"} if key else {})
        try:
            message = payload["message"]
            content = message.get("content", "")
            if not isinstance(content, str) or len(content) > 16000:
                raise ValueError()
            calls = []
            wire_calls = message.get("tool_calls", [])
            if not isinstance(wire_calls, list) or len(wire_calls) > 8:
                raise ValueError()
            for i, item in enumerate(wire_calls):
                fn = item["function"]
                aliases = {name.replace(".", "__"): name for name in TOOL_NAMES}
                if fn["name"] not in aliases:
                    raise ValueError()
                args = fn["arguments"]
                if isinstance(args, str):
                    args = json.loads(args)
                call = {"id": f"turn-{len(messages)}-{i}", "name": aliases[fn["name"]], "arguments": args}
                validate("tool-call", call)
                # Validate every call before executing any call in a model turn.
                validate(call["name"], args, "input")
                calls.append(call)
            # Ignore untrusted extra role/metadata supplied by the model.
            wire = {"role": "assistant", "content": content}
            if wire_calls:
                wire["tool_calls"] = wire_calls
            return Turn(calls, content, wire)
        except (KeyError, ValueError, TypeError, AttributeError):
            raise ToolFailure("invalid_model_output", "模型输出格式或工具参数无效；未执行本轮工具") from None


class RulesProvider:
    name = "offline_rules"

    def __init__(self, now, location, selected_place_id=None):
        self.now, self.location, self.selected_place_id = now, location, selected_place_id

    def next_turn(self, messages, tools):
        prompt = next(message["content"] for message in messages if message["role"] == "user")
        seen = [json.loads(m["content"]) for m in messages if m["role"] == "tool"]
        by_name = {r["tool"]: r for r in seen}
        start = self.now.replace(hour=0, minute=0, second=0, microsecond=0)
        period = {"start": start.isoformat(), "end": (start + timedelta(days=1)).isoformat()}
        wants_run = "跑步" in prompt or "适合运动" in prompt
        wants_navigation = "导航" in prompt
        if any(token in prompt for token in ("明天", "明早", "今晚", "晚上")) and (wants_run or wants_navigation):
            return Turn([], "离线路由当前仅支持今天白天的跑步评估；请明确为今天，或配置模型并核对日期。")
        if wants_run:
            for name, arguments in (("weather.forecast", {"location": self.location, "date": self.now.date().isoformat()}),
                                    ("health.summary", {"period": period})):
                if name not in by_name:
                    return self._call(name, arguments, seen)
        if wants_navigation:
            if "maps.search" not in by_name:
                match = re.search(r"导航到\s*(.+?)[。！!？?]*$", prompt)
                query = "公园" if "公园" in prompt else (match.group(1).strip("。 ") if match else "")
                if not query:
                    return Turn([], "请说明导航目的地。")
                return self._call("maps.search", {"query": query, "location": self.location, "radius_m": 3000}, seen)
            search = by_name["maps.search"]
            if search["status"] != "ok":
                return Turn([], "地点搜索失败；未生成导航。")
            candidates = search["data"]["candidates"]
            if not candidates:
                return Turn([], "未搜索到地点；请调整关键词或位置。")
            selected = next((p for p in candidates if p["id"] == self.selected_place_id), None)
            if len(candidates) > 1 and selected is None:
                return Turn([], "找到多个地点，请使用 --place-id 选择后重试；未擅自选择目的地。")
            if "maps.navigate" not in by_name:
                return self._call("maps.navigate", {"place_id": (selected or candidates[0])["id"], "mode": "walking"}, seen)
        if "提醒我" in prompt and "reminders.create" not in by_name:
            # Deliberately small, documented grammar; no guesses about unsupported date phrases.
            match = re.fullmatch(r"明(?:天|早)(?:早上|上午)?\s*(\d{1,2}|九)\s*(?:点|:00)提醒我(.+?)[。]?", prompt.strip())
            if not match:
                return Turn([], "离线提醒格式：明天早上9点提醒我开会；复杂日期请直接用 tool 命令或配置模型。")
            hour = 9 if match[1] == "九" else int(match[1])
            if hour > 23:
                return Turn([], "小时必须在 0–23 之间。")
            due = (start + timedelta(days=1)).replace(hour=hour)
            from .storage import digest
            return self._call("reminders.create", {"title": match[2], "due_at": due.isoformat(),
                "timezone": "Asia/Shanghai", "idempotency_key": digest({"title": match[2], "due_at": due.isoformat()})}, seen)
        if seen:
            return Turn([], "工具链已完成；请查看结构化结果，待确认动作尚未执行。")
        return Turn([], "离线路由支持今天跑步评估、导航和明早提醒；其他表达请配置模型 API。")

    @staticmethod
    def _call(name, arguments, seen):
        return Turn([{"id": f"rule-{len(seen) + 1}", "name": name, "arguments": arguments}])
