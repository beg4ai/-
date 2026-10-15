import argparse
from datetime import datetime
import json
from pathlib import Path
import sys
import sqlite3
from uuid import uuid4
from zoneinfo import ZoneInfo

from .adapters import AmapSearch, NavigationProposal, OpenMeteo
from .automation import AutomationEngine, WORKFLOWS
from .contracts import ContractError, TOOL_NAMES, validate, schema
from .coordinator import AgentCoordinator
from .executor import ExecutionContext, LocalToolExecutor, RemoteToolExecutor, ToolExecutor
from .planning import OllamaProvider, RulesProvider
from .storage import Store
from .rules import load_rules
from .tools import MockTools, ToolFailure, ToolRegistry


def read_json(value):
    if value.startswith("@"):
        return json.loads(Path(value[1:]).read_text(encoding="utf-8-sig"))
    return json.loads(value)


def parser():
    root = argparse.ArgumentParser(prog="东少", description="Windows First / iOS Native Ready / Local-first")
    sub = root.add_subparsers(dest="command", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--store", default=".agent/state.sqlite3", help="SQLite 路径，测试可用 :memory:")
    common.add_argument("--rules", help="自定义 automation-policy JSON 路径")
    common.add_argument("--now", help="仅用于 Mock/测试的带时区时间，默认 Asia/Shanghai 当前时间")
    common.add_argument("--latitude", type=float)
    common.add_argument("--longitude", type=float)
    common.add_argument("--coordinate-system", choices=["wgs84", "gcj02"], default="wgs84")
    common.add_argument("--public-api", action="store_true", help="显式启用网络天气/搜索；需要提供真实 WGS-84 位置")
    common.add_argument("--deny", action="append", default=[], choices=["location.share", "health.read", "calendar.read", "reminders.write"])
    common.add_argument("--mock-empty-health", action="store_true")
    common.add_argument("--mock-ambiguous", action="store_true")
    common.add_argument("--mock-no-amap", action="store_true")
    common.add_argument("--mock-rain", type=int, default=15)
    common.add_argument("--place-id", help="用户选择的搜索候选 ID，不能由模型审批")
    common.add_argument("--confirm", action="store_true", help="在终端逐项显示参数并询问 y/N；不是自动批准")
    ask = sub.add_parser("ask", parents=[common], help="自然语言调用工具")
    ask.add_argument("prompt", nargs="?", help="省略时交互输入")
    ask.add_argument("--llm", choices=["rules", "ollama"], default="rules")
    ask.add_argument("--share-private", action="store_true", help="同意将健康聚合/日程/提醒参数传给所配置模型")
    tool = sub.add_parser("tool", parents=[common], help="直接测试工具契约")
    tool.add_argument("name", choices=TOOL_NAMES)
    tool.add_argument("--args", required=True, help="JSON 或 @文件路径")
    event = sub.add_parser("event", parents=[common], help="注入一个事件；不安装系统自动化")
    event.add_argument("--file", help="独立 system-event JSON 文件")
    event.add_argument("--type", choices=WORKFLOWS)
    event.add_argument("--id")
    event.add_argument("--occurred-at")
    event.add_argument("--workout-id")
    sub.add_parser("replay", parents=[common], help="重试最多 20 个本地待处理事件，每事件最多 3 次")
    reports = sub.add_parser("reports", parents=[common], help="查询本地报告")
    reports.add_argument("--limit", type=int, default=10)
    sub.add_parser("schemas", help="显示六个工具的契约，不读取凭据")
    return root


def confirm_in_terminal(name, preview):
    print(f"\n需要确认 {name}：\n" + json.dumps(preview, ensure_ascii=False, indent=2), file=sys.stderr)
    if not sys.stdin.isatty():
        print("非交互输入，按取消处理。", file=sys.stderr)
        return False
    print("确认此操作？[y/N] ", end="", file=sys.stderr, flush=True)
    return input().strip().lower() in {"y", "yes", "是"}


def main(argv=None):
    # Make Chinese JSON predictable even on an English Windows console.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    args = parser().parse_args(argv)
    store = None
    try:
        if args.command == "schemas":
            output = {name: schema(name) for name in TOOL_NAMES}
        else:
            if args.public_api and args.now:
                raise ToolFailure("test_clock_forbidden", "真实 API 模式不能使用 Mock 时钟 --now")
            now = datetime.fromisoformat(args.now) if args.now else datetime.now(ZoneInfo("Asia/Shanghai"))
            if now.tzinfo is None:
                raise ToolFailure("timezone_required", "--now 必须带时区偏移量")
            now = now.astimezone(ZoneInfo("Asia/Shanghai"))
            explicit_location = args.latitude is not None and args.longitude is not None
            if (args.latitude is None) != (args.longitude is None):
                raise ToolFailure("location_required", "经纬度必须同时提供")
            if args.public_api and (not explicit_location or args.coordinate_system != "wgs84"):
                raise ToolFailure("location_required", "真实 API 模式需显式提供 WGS-84 经纬度；不会猜测当前位置")
            location = {"latitude": args.latitude if explicit_location else 31.23,
                        "longitude": args.longitude if explicit_location else 121.47,
                        "coordinate_system": args.coordinate_system}
            validate("weather.forecast", {"location": location, "date": now.date().isoformat()}, "input")
            if not 0 <= args.mock_rain <= 100:
                raise ToolFailure("invalid_mock_rain", "--mock-rain 应在 0–100 之间")
            if args.store != ":memory:":
                Path(args.store).parent.mkdir(parents=True, exist_ok=True)
            store = Store(args.store)
            local = LocalToolExecutor(MockTools(store, empty_health=args.mock_empty_health,
                     ambiguous=args.mock_ambiguous, amap_installed=not args.mock_no_amap, rain=args.mock_rain))
            registry = ToolRegistry(local)
            if args.public_api:
                registry.register("weather.forecast", RemoteToolExecutor(OpenMeteo()))
                registry.register("maps.search", RemoteToolExecutor(AmapSearch()))
                registry.register("maps.navigate", LocalToolExecutor(NavigationProposal()))
            executor = ToolExecutor(registry, store)
            context = ExecutionContext(now, selected_place_id=args.place_id)
            context.permissions.difference_update(args.deny)
            confirmation = confirm_in_terminal if args.confirm else None
            if args.command == "ask":
                provider = OllamaProvider() if args.llm == "ollama" else RulesProvider(now, location, args.place_id)
                prompt = args.prompt if args.prompt is not None else input("东少，请输入请求：\n")
                output = AgentCoordinator(executor, provider, share_private=args.share_private, rules=load_rules(args.rules)).run(prompt, context, location, confirmation)
            elif args.command == "tool":
                output = executor.execute({"id": str(uuid4()), "name": args.name, "arguments": read_json(args.args)}, context, confirmation)
            elif args.command in {"event", "replay"}:
                engine = AutomationEngine(executor, store, rules=load_rules(args.rules))
                if args.command == "replay":
                    output = engine.replay(context, location)
                else:
                    if args.file:
                        event = json.loads(Path(args.file).read_text(encoding="utf-8-sig"))
                    else:
                        if not args.type:
                            raise ToolFailure("missing_event_type", "event 需要 --type 或 --file")
                        event = {"contract_version": "1.0", "id": args.id or str(uuid4()), "type": args.type,
                                 "occurred_at": args.occurred_at or now.isoformat(), "received_at": now.isoformat(),
                                 "payload": {"workout_id": args.workout_id} if args.workout_id else {}}
                    output = engine.process(event, context, location)
                for report in output if isinstance(output, list) else [output]:
                    validate("workflow-report", report)
            elif args.command == "reports":
                if not 1 <= args.limit <= 100:
                    raise ToolFailure("invalid_limit", "limit 应在 1–100 之间")
                output = [json.loads(row["report"]) for row in store.db.execute(
                    "SELECT report FROM reports ORDER BY created_at DESC LIMIT ?", (args.limit,))]
        print(json.dumps(output, ensure_ascii=False, indent=2, allow_nan=False))
        if isinstance(output, dict) and output.get("status") in {"error", "denied", "unavailable", "failed", "retry_pending"}:
            return 1
        return 0
    except (ToolFailure, ContractError, ValueError, OSError, EOFError, sqlite3.Error) as error:
        code = error.code if isinstance(error, ToolFailure) else "invalid_input_or_storage"
        message = error.message if isinstance(error, ToolFailure) else "输入/契约/本地存储无效；未输出原始敏感内容"
        print(json.dumps({"status": "error", "error": {"code": code, "message": message}}, ensure_ascii=False))
        return 1
    finally:
        if store:
            store.close()
