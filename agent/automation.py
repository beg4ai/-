"""Explicit event processing, not a background daemon or an iOS scheduler."""
from datetime import datetime, timedelta
import json
from uuid import uuid4
from zoneinfo import ZoneInfo

from .contracts import validate
from .coordinator import running_assessment
from .storage import digest
from .tools import ToolFailure
from .rules import load_rules

ZONE = ZoneInfo("Asia/Shanghai")
WORKFLOWS = {"alarm.stopped": "morning_brief", "location.left_home": "leaving_home",
             "health.workout_completed": "workout_analysis", "schedule.evening": "daily_review"}


class AutomationEngine:
    def __init__(self, executor, store, *, rules=None):
        self.executor, self.store = executor, store
        self.rules = rules or load_rules()
        self.cooldown = timedelta(minutes=self.rules["cooldown_minutes"])
        self.quiet_start, self.quiet_end = self.rules["quiet_start"], self.rules["quiet_end"]

    def process(self, event, context, location):
        validate("system-event", event)
        occurred = datetime.fromisoformat(event["occurred_at"]).astimezone(ZONE)
        received = datetime.fromisoformat(event["received_at"])
        if occurred > received or received > context.now + timedelta(minutes=5):
            raise ToolFailure("invalid_event_time", "事件时间不得晚于接收时间，接收时间不得在未来")
        if event["type"] == "health.workout_completed" and not event["payload"].get("workout_id"):
            raise ToolFailure("missing_workout_id", "运动事件必须带有 workout UUID")
        kind = WORKFLOWS[event["type"]]
        if kind in {"morning_brief", "daily_review"}:
            key = f"{kind}:{occurred.date()}"
        elif kind == "workout_analysis":
            key = f"workout:{event['payload']['workout_id']}"
        else:
            key = f"away:{event['id']}"
        # Single CLI writer; atomic claim/report/notification decision across invocations.
        self.store.db.execute("BEGIN IMMEDIATE")
        self.store.in_workflow = True
        try:
            row = self.store.db.execute("SELECT * FROM events WHERE key=?", (key,)).fetchone()
            if row and row["status"] == "completed":
                report = json.loads(row["report"])
                report.update(status="duplicate", notification={"should_notify": False, "reason": "deduplicated", "delivered": False})
                self.store.db.commit()
                return report
            if row and row["attempts"] >= self.rules["max_event_attempts"]:
                self.store.db.commit()
                return self._report(key, kind, context, "failed", "事件已达尝试上限，请检查配置后重新提交新事件", [])
            if not row:
                self.store.db.execute("INSERT INTO events(key,event,status) VALUES(?,?,?)",
                                      (key, json.dumps(event, ensure_ascii=False), "pending"))
            self.store.db.execute("UPDATE events SET attempts=attempts+1 WHERE key=?", (key,))
            start = occurred.replace(hour=0, minute=0, second=0, microsecond=0)
            period = {"start": start.isoformat(), "end": (start + timedelta(days=1)).isoformat()}
            results = []

            def execute(name, args):
                result = self.executor.execute({"id": f"event-{len(results)}", "name": name, "arguments": args}, context)
                results.append(result)
                return result

            weather = health = calendar = None
            # Delayed offline events query the event date, not whichever day replay happens.
            if kind in {"morning_brief", "leaving_home"}:
                weather = execute("weather.forecast", {"location": location, "date": occurred.date().isoformat()})
            if kind in {"morning_brief", "workout_analysis", "daily_review"}:
                health = execute("health.summary", {"period": period})
            if kind in {"morning_brief", "leaving_home", "daily_review"}:
                calendar = execute("calendar.events", {"period": period})
            retryable = any(r["error"] and r["error"]["retryable"] for r in results)
            if retryable:
                report = self._report(key, kind, context, "retry_pending", "数据暂不可用；事件已保存在本地，使用 replay 重试", results)
                self.store.db.execute("UPDATE events SET status='pending',report=? WHERE key=?",
                                      (json.dumps(report, ensure_ascii=False), key))
                self.store.db.commit()
                return report
            notes = []
            if weather:
                if weather["status"] == "ok":
                    notes.append(f"天气：{weather['data']['temperature_c']}°C，降雨概率 {weather['data']['precipitation_probability']}%")
                else:
                    notes.append("天气不可用")
            if health:
                if health["status"] == "ok":
                    values = health["data"]
                    notes.append(f"健康聚合：睡眠 {values['sleep_hours'] if values['sleep_hours'] is not None else '缺失'} 小时，"
                                 f"步数 {values['steps'] if values['steps'] is not None else '缺失'}，"
                                 f"运动 {values['workout_minutes'] if values['workout_minutes'] is not None else '缺失'} 分钟")
                else:
                    notes.append("健康数据未授权或不可用，不能当作零")
            if calendar:
                notes.append(f"日程 {len(calendar['data']['events'])} 项" if calendar["status"] == "ok" else "日程不可用")
            if kind == "workout_analysis":
                workout = next((w for w in health["data"].get("workouts", [])
                                if w["id"] == event["payload"]["workout_id"]), None) if health["status"] == "ok" else None
                if workout:
                    notes.append(f"本次运动 {workout['duration_minutes']} 分钟，距离 {workout['distance_m'] if workout['distance_m'] is not None else '缺失'} 米")
                    if workout["distance_m"] and workout["duration_minutes"]:
                        notes.append(f"平均配速 {workout['duration_minutes'] / (workout['distance_m'] / 1000):.1f} 分钟/公里；仅为速度统计，不判定运动类型或强度")
                else:
                    notes.append("对应运动尚未查询到；不将当日聚合冒充单次运动")
                    if health["status"] == "ok" and health["data"]["availability"] != "unknown":
                        report = self._report(key, kind, context, "retry_pending", "运动同步尚未完成；保留事件等待 replay", results)
                        self.store.db.execute("UPDATE events SET status='pending',report=? WHERE key=?", (json.dumps(report, ensure_ascii=False), key))
                        self.store.db.commit()
                        return report
                notes.append("非诊断建议：按体感恢复，异常不适时停止运动")
            if kind == "daily_review":
                reminders = self.store.db.execute("SELECT count(*) FROM reminders").fetchone()[0]
                notes.append(f"本地演示提醒记录 {reminders} 项（全部留存，非系统未完成待办）；系统待办读取尚未接入")
            report = self._report(key, kind, context, "completed", "；".join(notes), results)
            risks = []
            if weather and weather["status"] == "ok":
                w = weather["data"]
                if w["precipitation_probability"] >= self.rules["rain_threshold"]:
                    risks.append("rain")
                if w["wind_kph"] >= self.rules["wind_threshold_kph"]:
                    risks.append("wind")
                if "雷暴" in w["condition"]:
                    risks.append("thunderstorm")
            now = context.now.astimezone(ZONE)
            quiet = (now.hour >= self.quiet_start or now.hour < self.quiet_end) if self.quiet_start > self.quiet_end else self.quiet_start <= now.hour < self.quiet_end
            should_notify, reason = (not quiet), ("quiet_hours" if quiet else "new_report")
            fingerprint = digest({"date": str(occurred.date()), "risks": risks} if kind == "leaving_home" else key)
            previous = self.store.db.execute("SELECT * FROM notification_history WHERE kind=?", (kind,)).fetchone()
            if kind == "leaving_home":
                if not risks:
                    should_notify, reason = False, "no_new_risk"
                elif previous and previous["fingerprint"] == fingerprint:
                    should_notify, reason = False, "unchanged_risk"
                elif previous and context.now - datetime.fromisoformat(previous["issued_at"]) < self.cooldown:
                    should_notify, reason = False, "cooldown"
            if kind == "daily_review" and not any(
                r["status"] == "ok" and ((r["tool"] == "calendar.events" and r["data"]["events"]) or
                   (r["tool"] == "health.summary" and (r["data"]["steps"] or r["data"]["workout_minutes"]))) for r in results):
                should_notify, reason = False, "low_information"
            if context.now - occurred > timedelta(hours=self.rules["stale_event_hours"]):
                should_notify, reason = False, "stale_event"
            report["notification"] = {"should_notify": should_notify, "reason": reason, "delivered": False}
            report["assessment"] = running_assessment(weather, health, self.rules) if kind == "morning_brief" else None
            if should_notify:
                self.store.db.execute("INSERT OR REPLACE INTO notification_history VALUES(?,?,?)",
                                      (kind, context.now.isoformat(), fingerprint))
            encoded = json.dumps(report, ensure_ascii=False)
            self.store.db.execute("INSERT OR REPLACE INTO reports VALUES(?,?,?,?)",
                                  (key, kind, context.now.isoformat(), encoded))
            self.store.db.execute("UPDATE events SET status='completed',report=? WHERE key=?", (encoded, key))
            self.store.db.commit()
            return report
        except Exception:
            self.store.db.rollback()
            raise
        finally:
            self.store.in_workflow = False

    @staticmethod
    def _report(key, kind, context, status, summary, results):
        return {"contract_version": "1.0", "report_id": key, "workflow": kind, "status": status,
                "trace_id": context.trace_id, "created_at": context.now.isoformat(), "summary": summary,
                "tool_results": results, "assessment": None,
                "notification": {"should_notify": False, "reason": status, "delivered": False},
                "contains_mock_data": any(r["is_mock"] for r in results)}

    def replay(self, context, location):
        rows = self.store.db.execute("SELECT event FROM events WHERE status='pending' AND attempts<? ORDER BY rowid LIMIT 20", (self.rules["max_event_attempts"],)).fetchall()
        return [self.process(json.loads(row["event"]), context, location) for row in rows]
