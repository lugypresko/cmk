from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "runs" / "001-human-gates"
TZ = ZoneInfo("Asia/Jerusalem")


def out_dir() -> Path:
    p = Path(os.environ.get("CMK_OUT") or RUN / "out")
    p.mkdir(parents=True, exist_ok=True)
    return p


def now() -> dt.datetime:
    v = os.environ.get("CMK_NOW")
    return dt.datetime.fromisoformat(v).astimezone(TZ) if v else dt.datetime.now(TZ).replace(microsecond=0)


def iso(t: dt.datetime) -> str:
    return t.isoformat(timespec="seconds")


def sha_file(p: Path) -> str:
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def load(name: str, default=None):
    p = out_dir() / name
    return json.loads(p.read_text()) if p.exists() else default


def save(name: str, data) -> Path:
    p = out_dir() / name
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return p


def event(kind: str, actor: str, **data):
    """Append-only journal of every state change (events.jsonl)."""
    p = out_dir() / "events.jsonl"
    seq = sum(1 for _ in p.open()) + 1 if p.exists() else 1
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"seq": seq, "ts": iso(now()), "actor": actor, "event": kind, **data}, ensure_ascii=False) + "\n")


class GateError(SystemExit):
    def __init__(self, msg):
        super().__init__(f"BLOCKED: {msg}")
