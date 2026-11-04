"""Shared helpers: context loading, text normalisation, findings."""
from __future__ import annotations

import json
import re
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent
ROOT = PKG_DIR.parent
FIXTURES = PKG_DIR / "fixtures"

HEB_CHAR = re.compile(r"[\u0590-\u05FF]")
HEB_LETTER = re.compile(r"[\u05D0-\u05EA]")
LAT_LETTER = re.compile(r"[A-Za-z]")
URL_RE = re.compile(r"https?://\S+")
# Emoji-ish: pictographs, dingbats, symbols. Arrows (← →) used as list bullets are NOT emojis.
EMOJI_RE = re.compile("[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F000-\U0001F2FF]")
MARKER_RE = re.compile(r"⟦[^⟧]*⟧")

SEVERITY = {"block": "blocker"}


def load_json(path: Path | str):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_context(fixtures_dir: Path | str | None = None) -> dict:
    """Guardian read-context. Fixtures are exported from the local PGlite DB by
    scripts/export_fixtures.mjs (brand_voice, icp, format_specs, thresholds) plus
    guardian_checklist.json from the repo root."""
    d = Path(fixtures_dir) if fixtures_dir else FIXTURES
    ctx = {
        "checklist": load_json(d / "checklist.json"),
        "format_specs": load_json(d / "format_specs.json"),
        "brand_voice": load_json(d / "brand_voice.json"),
        "icp": load_json(d / "icp_profile.json"),
        "thresholds": load_json(d / "thresholds.json"),
    }
    perf = ROOT / "seed_performance_stripe_minions.json"
    ctx["performance_seed"] = load_json(perf) if perf.exists() else None
    ctx["checks"] = {c["id"]: c for c in ctx["checklist"]["checks"]}
    return ctx


def load_facts(path: Path | str | None) -> list[dict]:
    """Accepts a list of facts or {facts: [...]}. Field aliases: claim/claim_text/statement."""
    p = Path(path) if path else FIXTURES / "approved_facts_db.json"
    data = load_json(p)
    facts = data["facts"] if isinstance(data, dict) else data
    out = []
    for f in facts:
        out.append({
            "id": f.get("id") or f.get("fact_id"),
            "fact_key": f.get("fact_key", ""),
            "category": f.get("category"),
            "statement_en": f.get("statement_en") or f.get("claim_text") or f.get("claim") or "",
            "statement_he": f.get("statement_he") or "",
            "status": f.get("status", "draft"),
            "confidentiality": f.get("confidentiality") or f.get("visibility") or "internal",
            "valid_until": f.get("valid_until"),
            "usage_scope": f.get("usage_scope") or ["public_posts"],
            "source_url": f.get("source_url"),
        })
    return out


def fact_usable(f: dict, now: datetime | None = None) -> tuple[bool, str]:
    """Mirror of cmk.usable_facts_v (migration 005 §6) + usage_scope public_posts."""
    now = now or datetime.now(timezone.utc)
    if f["status"] != "approved":
        return False, f"status={f['status']}"
    if f["confidentiality"] != "public":
        return False, f"confidentiality={f['confidentiality']}"
    vu = f.get("valid_until")
    if vu:
        try:
            dt = datetime.fromisoformat(str(vu).replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            if dt <= now:
                return False, f"expired (valid_until={vu})"
        except ValueError:
            return False, f"unparseable valid_until={vu}"
    if "public_posts" not in (f.get("usage_scope") or []):
        return False, "usage_scope excludes public_posts"
    return True, "ok"


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s or "")
    s = s.replace("״", '"').replace("“", '"').replace("”", '"').replace("’", "'").replace("‘", "'")
    return re.sub(r"\s+", " ", s).strip()


def paragraphs(text: str) -> list[str]:
    return [p.strip() for p in re.split(r"\n\s*\n", text or "") if p.strip()]


_SENT_SPLIT = re.compile(r"(?<=[.?!:])\s+(?=[\"'״A-Z\u05D0-\u05EA←→\-*(])|\n+")


def sentences(text: str) -> list[str]:
    out = []
    for part in _SENT_SPLIT.split(text or ""):
        part = part.strip().lstrip("←→-•* ").strip()
        if len(part) >= 3:
            out.append(part)
    return out


def he_ratio(text: str, allowlist: list[str]) -> tuple[float, int, int]:
    t = text or ""
    for tok in sorted(allowlist, key=len, reverse=True):
        t = re.sub(r"(?<![A-Za-z])" + re.escape(tok) + r"(?![A-Za-z])", " ", t)
    he = len(HEB_LETTER.findall(t))
    la = len(LAT_LETTER.findall(t))
    return (he / (he + la) if he + la else 1.0), he, la


def finding(check_id: str, ftype: str, severity: str, message: str, field: str | None = None,
            excerpt: str | None = None, suggestion: str | None = None, points_delta: int | None = None) -> dict:
    f = {"check_id": check_id, "type": ftype, "severity": severity, "message": message}
    if field:
        f["field"] = field
    if excerpt:
        f["excerpt"] = excerpt[:240]
    if suggestion:
        f["suggestion"] = suggestion
    if points_delta is not None:
        f["points_delta"] = points_delta
    return f


def text_fields(piece: dict) -> list[tuple[str, str]]:
    """Every scannable text field (guardian_rules §11: payload text scanned like body)."""
    out = []
    for k in ("title", "hook", "thesis", "body", "cta", "ps"):
        v = piece.get(k)
        if isinstance(v, str) and v.strip():
            out.append((k, v))
    for i, s in enumerate(piece.get("slides") or []):
        out.append((f"slides[{i}].headline", s.get("headline") or ""))
        if s.get("text"):
            out.append((f"slides[{i}].text", s["text"]))
    for i, kp in enumerate(piece.get("key_points") or []):
        out.append((f"key_points[{i}]", kp if isinstance(kp, str) else json.dumps(kp, ensure_ascii=False)))
    payload = piece.get("payload")
    if isinstance(payload, dict):
        for k, v in payload.items():
            if isinstance(v, str):
                out.append((f"payload.{k}", v))
    return out


def all_text(piece: dict) -> str:
    return "\n\n".join(v for _, v in text_fields(piece))


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
