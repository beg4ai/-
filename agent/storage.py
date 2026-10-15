"""Local SQLite; audit contains hashes/status, never raw prompts or health records."""
import hashlib
import json
import sqlite3


def digest(value):
    try:
        canonical = json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False)
    except (ValueError, TypeError):
        # Invalid parameters still get an audit record without serializing unsafe objects.
        canonical = '{"invalid_json":true}'
    return hashlib.sha256(canonical.encode()).hexdigest()


class Store:
    def __init__(self, path=":memory:"):
        self.db = sqlite3.connect(str(path))
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS audit (
                id INTEGER PRIMARY KEY, trace_id TEXT, tool TEXT, risk TEXT,
                arguments_hash TEXT, status TEXT, error_code TEXT, created_at TEXT);
            CREATE TABLE IF NOT EXISTS reminders (
                key TEXT PRIMARY KEY, arguments_hash TEXT NOT NULL, result TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS events (
                key TEXT PRIMARY KEY, event TEXT NOT NULL, status TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0, report TEXT);
            CREATE TABLE IF NOT EXISTS reports (
                key TEXT PRIMARY KEY, kind TEXT NOT NULL, created_at TEXT NOT NULL, report TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS notification_history (
                kind TEXT PRIMARY KEY, issued_at TEXT NOT NULL, fingerprint TEXT NOT NULL);
        """)

    def close(self):
        self.db.close()

    def audit(self, trace_id, tool, risk, arguments, status, code, now):
        self.db.execute("INSERT INTO audit VALUES(NULL,?,?,?,?,?,?,?)",
                        (trace_id, tool, risk, digest(arguments), status, code, now))
        # Workflow owns a transaction when processing an event.
        if not getattr(self, "in_workflow", False):
            self.db.commit()

    def reminder(self, args, now):
        old = self.db.execute("SELECT * FROM reminders WHERE key=?", (args["idempotency_key"],)).fetchone()
        if old:
            if old["arguments_hash"] != digest(args):
                raise ValueError("idempotency_conflict")
            return json.loads(old["result"])
        result = {"id": "mock-" + digest(args)[:16], "title": args["title"],
                  "due_at": args["due_at"], "timezone": args["timezone"], "simulated": True}
        self.db.execute("INSERT INTO reminders VALUES(?,?,?)",
                        (args["idempotency_key"], digest(args), json.dumps(result, ensure_ascii=False)))
        if not getattr(self, "in_workflow", False):
            self.db.commit()
        return result
