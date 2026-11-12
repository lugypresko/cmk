"""SpecGate v0 — deterministic, code-checkable rules from guardian_checklist.json +
format_specs. Any `blocker` finding => verdict 'block'.

Covers: S-01 schema, S-02 unresolved placeholders (Phase-0 addition), S-03 active
format_spec exists, B-02 pricing, B-03/B-04/B-05 (partial regex heuristics only),
B-06/L-01 language ratio, L-02 spelling mix, B-07 guarantees, B-09 approval actor,
B-11 hard limits, B-12 analytics viewer data, F-T1..F-T7 text_post, F-C1..F-C7 carousel,
R-01 RenderQA (contracts v2), CTA-01/02/03/05 (regex part), L-05 twin numbers (with --twin).

Not here (LLM judge in production): B-10 disparagement, V-03/V-06, ICP-P*, L-03, CTA-04 —
EditorialGuardian handles those as scores/warnings; they never block in v0.
"""
from __future__ import annotations

import re

from .common import (EMOJI_RE, HEB_CHAR, MARKER_RE, URL_RE, all_text, finding, he_ratio, norm,
                     paragraphs, text_fields)

CP_FORMATS = {"text_post", "carousel", "thread", "short_video_script", "article"}
CP_CHANNELS = {"linkedin", "instagram", "facebook", "x", "website"}
CP_STATUS = {"draft", "in_review", "needs_changes", "approved", "scheduled", "published", "rejected", "archived"}
CA_STATUS = {"draft", "in_review", "needs_changes", "approved", "rejected", "archived"}
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
PLACEHOLDER = re.compile(r"⟦[^⟧]*⟧|\b(TODO|TBD|XXX|FIXME|lorem ipsum)\b|\{\{[^}]+\}\}", re.I)
US_UK = [("color", "colour"), ("behavior", "behaviour"), ("organize", "organise"), ("organization", "organisation"),
         ("optimize", "optimise"), ("prioritize", "prioritise"), ("analyze", "analyse"), ("center", "centre"),
         ("recognize", "recognise"), ("favorite", "favourite"), ("labor", "labour"), ("realize", "realise")]
HUMAN_APPROVERS = {"itay", "itay foyerstein", "human"}


def _spec_for(piece: dict, ctx: dict) -> dict | None:
    for s in ctx["format_specs"]:
        if (s["format"], s["channel"], s["language"]) == (piece.get("format"), piece.get("channel"), piece.get("language")) and s["is_active"]:
            return s
    return None


def _schema(piece: dict, strict: bool) -> list[dict]:
    F = []
    db_sev = "blocker" if strict else "info"
    if piece.get("contract") == "cmk/CoreAsset":
        for k in ("id", "icp_profile_id", "brand_voice_id"):
            if not piece.get(k):
                F.append(finding("S-01", "format", db_sev, f"CoreAsset.{k} missing (assigned at DB insert; file mode)", field=k))
        if not piece.get("title"):
            F.append(finding("S-01", "format", "blocker", "CoreAsset.title required", field="title"))
        elif len(piece["title"]) > 200:
            F.append(finding("S-01", "format", "blocker", "title > 200 chars", field="title"))
        if piece.get("thesis") and len(piece["thesis"]) > 280:
            F.append(finding("S-01", "format", "blocker", f"thesis {len(piece['thesis'])} chars > 280", field="thesis"))
        if piece.get("primary_language") not in ("en", "he"):
            F.append(finding("S-01", "format", "blocker", "primary_language must be en|he", field="primary_language"))
        if not (piece.get("body") or "").strip():
            F.append(finding("S-01", "format", "blocker", "body required for primary language", field="body"))
        if piece.get("status") not in CA_STATUS:
            F.append(finding("S-01", "format", "blocker", f"CoreAsset status '{piece.get('status')}' invalid (never scheduled/published)", field="status"))
        if len(piece.get("key_points") or []) > 7:
            F.append(finding("S-01", "format", "blocker", "key_points > 7", field="key_points"))
    else:
        for k in ("id", "core_asset_id", "format_spec_id"):
            if not piece.get(k):
                F.append(finding("S-01", "format", db_sev, f"ContentPiece.{k} missing (assigned at DB insert; file mode)", field=k))
        if piece.get("format") not in CP_FORMATS:
            F.append(finding("S-01", "format", "blocker", f"format '{piece.get('format')}' not in ContentPiece enum", field="format"))
        if piece.get("channel") not in CP_CHANNELS:
            F.append(finding("S-01", "format", "blocker", f"channel '{piece.get('channel')}' invalid", field="channel"))
        if piece.get("language") not in ("en", "he"):
            F.append(finding("S-01", "format", "blocker", "language must be en|he", field="language"))
        if not isinstance(piece.get("body"), str) or not piece["body"].strip():
            F.append(finding("S-01", "format", "blocker", "body required (string)", field="body"))
        if piece.get("status") not in CP_STATUS:
            F.append(finding("S-01", "format", "blocker", f"status '{piece.get('status')}' invalid", field="status"))
        rev = piece.get("revision", 1)
        if not isinstance(rev, int) or rev < 1:
            F.append(finding("S-01", "format", "blocker", "revision must be integer >= 1", field="revision"))
        hs = piece.get("hashtags") or []
        if len(hs) > 5:
            F.append(finding("S-01", "format", "blocker", "hashtags > 5 (schema max)", field="hashtags"))
        for h in hs:
            if not re.match(r"^#\S+$", str(h)):
                F.append(finding("S-01", "format", "blocker", f"hashtag '{h}' must match ^#\\S+$", field="hashtags"))
        if piece.get("format") == "carousel":
            sl = piece.get("slides")
            if not isinstance(sl, list) or not sl:
                F.append(finding("B-11", "format", "blocker", "carousel requires slides", field="slides"))
            else:
                for i, s in enumerate(sl):
                    if not isinstance(s.get("n"), int) or s["n"] < 1 or not (s.get("headline") or "").strip():
                        F.append(finding("S-01", "format", "blocker", "slide needs integer n>=1 and headline", field=f"slides[{i}]"))
        if piece.get("status") in ("approved", "scheduled", "published"):
            missing = [k for k in ("brand_score", "icp_relevance_score", "approved_by", "approved_at") if piece.get(k) in (None, "")]
            if missing:
                sev = "blocker" if (strict or any(k in missing for k in ("approved_by", "approved_at"))) else "major"
                F.append(finding("S-01", "format", sev,
                                 f"status={piece['status']} requires {', '.join(missing)} (DB CHECK would reject this row)",
                                 field="status", suggestion="Store this GuardianReport's scores with the row before insert."))
    for fid in piece.get("fact_ids") or []:
        if not UUID.match(str(fid)):
            F.append(finding("S-01", "format", "blocker", f"fact_id '{fid}' is not a uuid", field="fact_ids"))
    return F


def check(piece: dict, ctx: dict, strict: bool = False, media_qa: str | None = None, twin: dict | None = None) -> dict:
    F: list[dict] = []
    checks = ctx["checks"]
    lang = piece.get("language")
    fmt = piece.get("format")
    is_core = piece.get("contract") == "cmk/CoreAsset"
    body = piece.get("body") or ""
    txt = all_text(piece)

    # S-01 schema
    F += _schema(piece, strict)

    # S-03 active format spec
    spec = None
    if not is_core:
        spec = _spec_for(piece, ctx)
        if spec is None:
            F.append(finding("S-03", "format", "blocker", f"no active format_specs row for ({fmt}, {piece.get('channel')}, {lang})"))
        elif not spec.get("limits_verified"):
            F.append(finding("S-03", "format", "info", "format_specs.limits_verified=false (platform limits are house defaults, not re-verified)"))

    # S-02 unresolved placeholders / markers
    for field, v in text_fields(piece):
        for m in PLACEHOLDER.finditer(v):
            F.append(finding("S-02", "other", "blocker", f"unresolved placeholder {m.group(0)!r}", field=field,
                             excerpt=v[max(0, m.start() - 40): m.end() + 80],
                             suggestion="Resolve (Itay confirms the anecdote) or delete the paragraph before review."))

    # B-02 pricing
    rx = re.compile(checks["B-02"]["params"]["regex"], re.I)
    for field, v in text_fields(piece):
        for m in rx.finditer(v):
            F.append(finding("B-02", "fact", "blocker", f"pricing/discount/free-offer pattern {m.group(0)!r}", field=field,
                             excerpt=v[max(0, m.start() - 40): m.end() + 40]))

    # B-07 guarantees
    rx = re.compile(checks["B-07"]["params"]["regex"], re.I)
    for field, v in text_fields(piece):
        for m in rx.finditer(v):
            F.append(finding("B-07", "voice", "blocker", f"guaranteed-outcome language {m.group(0)!r}", field=field,
                             excerpt=v[max(0, m.start() - 40): m.end() + 40]))

    # B-03/B-04/B-05 partial heuristics (production: NER + LLM judge)
    heur = [
        ("B-03", "confidentiality", r"\b(my|a|our) (coaching )?client\b[^.\n]{0,60}\b(at|from)\s+[A-Z][\w.&-]+|(לקוח|לקוחה)(\s+\S+){0,4}\s+ב-?[A-Za-z][\w.&-]+"),
        ("B-04", "confidentiality", r"[\"“][^\"”]{8,}[\"”]\s*[—–-]\s*(VP|CTO|CEO|Director|Head|Manager|EM|סמנכ\"?ל|מנהל|מנכ\"?ל)"),
        ("B-05", "confidentiality", r"\b(I )?(told|shared with|reported to) (their|the|his|her) (CEO|CTO|boss|company|sponsor|HR)\b|סיפרתי ל(מנכ\"?ל|הנהלה|מנהל שלו|מנהלת שלה)|דיווחתי ל"),
    ]
    for cid, t, pat in heur:
        r = re.compile(pat, re.I)
        for field, v in text_fields(piece):
            for m in r.finditer(v):
                F.append(finding(cid, t, "blocker", f"{cid} heuristic hit (partial regex; LLM judge in prod)", field=field,
                                 excerpt=v[max(0, m.start() - 30): m.end() + 30]))

    # B-12 analytics viewer data
    b12 = re.compile(r"\b(viewers?|people|readers?|folks)\s+(from|at)\s+[A-Z][\w.&-]+|\bwho (viewed|read) my (last )?post|צפו בפוסט|קראו את הפוסט( האחרון)? (מ|ב)", re.I)
    demo_strings = []
    perf = ctx.get("performance_seed") or {}
    for vals in (perf.get("demographics_top") or {}).values():
        demo_strings += [v for v in vals if isinstance(v, str)]
    for field, v in text_fields(piece):
        for m in b12.finditer(v):
            F.append(finding("B-12", "confidentiality", "blocker", "analytics viewer data used as content", field=field, excerpt=m.group(0)))
        for d in demo_strings:
            if d in v:
                F.append(finding("B-12", "confidentiality", "blocker", f"verbatim analytics demographic {d!r}", field=field))

    # B-06 / L-01 language
    allow = checks["B-06"]["params"]["tech_allowlist"] + ["Slack", "OK", "WHAT", "HOW", "Lints", "lints"]
    for field, v in text_fields(piece):
        if lang == "en" and HEB_CHAR.search(v):
            F.append(finding("B-06", "language", "blocker", "EN piece contains Hebrew characters", field=field,
                             excerpt=HEB_CHAR.search(v).group(0)))
    if lang == "he":
        r, he, la = he_ratio(txt, allow)
        p = checks["B-06"]["params"]
        if r < p["he_block_below"]:
            F.append(finding("B-06", "language", "blocker", f"HE letter ratio {r:.2f} < {p['he_block_below']}"))
        elif r < p["he_warn_below"]:
            F.append(finding("L-01", "language", "major", f"HE letter ratio {r:.2f} in 0.40–0.60 band"))
        else:
            F.append(finding("L-01", "language", "info", f"HE letter ratio {r:.2f} (he={he}, latin={la} after tech allowlist) OK"))
    if lang == "en":
        low = txt.lower()
        us = [a for a, b in US_UK if re.search(r"\b" + a, low)]
        uk = [b for a, b in US_UK if re.search(r"\b" + b, low)]
        if us and uk:
            F.append(finding("L-02", "language", "minor", f"mixed US/UK spelling: US {us} vs UK {uk}"))

    # B-09 approval actor
    if piece.get("status") in ("approved", "scheduled", "published"):
        ab = str(piece.get("approved_by") or "").strip().lower()
        if ab and ab not in HUMAN_APPROVERS:
            F.append(finding("B-09", "other", "blocker", f"approved_by '{piece.get('approved_by')}' is not a known human approver", field="approved_by"))
        elif ab:
            F.append(finding("B-09", "other", "info", f"approved_by={piece.get('approved_by')} (human). File mode cannot verify the actor; DB trigger enforces cmk.actor_type=human."))

    # B-11 hard limits
    if fmt == "text_post" and len(body) > checks["B-11"]["params"]["max_chars"]:
        F.append(finding("B-11", "format", "blocker", f"body {len(body)} chars > 3000", field="body"))
    if fmt == "carousel":
        mx = (spec or {}).get("max_slides") or checks["B-11"]["params"]["default_max_slides"]
        if len(piece.get("slides") or []) > mx:
            F.append(finding("B-11", "format", "blocker", f"{len(piece['slides'])} slides > max_slides {mx}", field="slides"))

    paras = paragraphs(body)
    closing = paras[-1] if paras else ""

    # text_post format
    if fmt == "text_post":
        hook = piece.get("hook")
        if hook:
            if not norm(body).startswith(norm(hook)):
                F.append(finding("F-T1", "format", "major", "hook does not equal the start of body",
                                 field="hook", excerpt=f"hook={norm(hook)[:90]!r} | body starts={norm(body)[:90]!r}",
                                 suggestion="Make body open with the approved hook (or update the hook field)."))
            if len(hook) > 200:
                F.append(finding("F-T1", "format", "minor", f"hook {len(hook)} chars > 200", field="hook"))
        first_line = body.splitlines()[0] if body else ""
        if len(first_line) > 120:
            F.append(finding("F-T1", "format", "minor", f"first line {len(first_line)} chars > 120", field="body"))
        mn, mx = (spec or {}).get("min_chars") or 600, (spec or {}).get("max_chars") or 2200
        if not (mn <= len(body) <= mx):
            F.append(finding("F-T2", "format", "minor", f"body {len(body)} chars outside {mn}–{mx}", field="body"))
        for p in paras:
            if len(p) > 600 and "\n" not in p:
                F.append(finding("F-T3", "format", "minor", f"paragraph {len(p)} chars with no line break", excerpt=p[:80]))
            elif len(p) > 350:
                F.append(finding("F-T3", "format", "minor", f"paragraph {len(p)} chars > 350 (house default)", excerpt=p[:80]))
        if len(piece.get("hashtags") or []) > 3:
            F.append(finding("F-T4", "format", "minor", "more than 3 hashtags"))
        for m in URL_RE.finditer(body):
            F.append(finding("F-T5", "format", "minor", "external link in body; move to first comment", excerpt=m.group(0)))
        if len(EMOJI_RE.findall(body)) > 3:
            F.append(finding("F-T6", "format", "minor", "more than 3 emojis"))
        cta = piece.get("cta")
        if cta and norm(cta) not in norm(closing):
            F.append(finding("F-T7", "cta", "minor", "cta field does not match closing paragraph", field="cta",
                             excerpt=f"cta={norm(cta)[:80]!r} | closing={norm(closing)[:80]!r}"))

    # carousel format
    if fmt == "carousel":
        sl = piece.get("slides") or []
        ns = [s.get("n") for s in sl]
        if ns != list(range(1, len(ns) + 1)):
            F.append(finding("F-C1", "format", "blocker", f"slide numbers not sequential from 1: {ns}", field="slides"))
        if not (5 <= len(sl) <= 10):
            F.append(finding("F-C2", "format", "minor", f"{len(sl)} slides (5–10 recommended)"))
        if sl:
            lim = 50 if lang == "he" else 60
            h1 = sl[0].get("headline", "")
            if len(h1) > lim:
                F.append(finding("F-C3", "format", "minor", f"slide 1 headline {len(h1)} chars > {lim}", field="slides[0].headline"))
            for i, s in enumerate(sl):
                if len(s.get("headline", "")) > 80:
                    F.append(finding("F-C4", "format", "minor", f"headline {len(s['headline'])} > 80", field=f"slides[{i}].headline"))
                if len(s.get("text") or "") > 300:
                    F.append(finding("F-C4", "format", "minor", f"text {len(s['text'])} > 300", field=f"slides[{i}].text"))
                if lang == "he" and re.match(r"^[A-Za-z]", s.get("headline", "")):
                    F.append(finding("F-C7", "format", "minor", "HE headline starts with an English token (RTL risk)", field=f"slides[{i}].headline"))
            last = sl[-1]
            last_txt = norm(last.get("headline", "") + " " + (last.get("text") or ""))
            cta = norm(piece.get("cta") or "")
            if "?" not in last_txt:
                F.append(finding("F-C5", "cta", "minor", "last slide is not a question"))
            elif cta:
                tok = lambda s: set(re.findall(r"[\w\u0590-\u05FF]{3,}", s.lower()))
                ov = len(tok(cta) & tok(last_txt)) / max(1, len(tok(cta)))
                if ov < 0.4:
                    F.append(finding("F-C5", "cta", "minor", f"last slide only loosely matches cta (token overlap {ov:.2f})"))
        if not (150 <= len(body) <= 1300):
            F.append(finding("F-C6", "format", "minor", f"caption {len(body)} chars outside 150–1300", field="body"))
        # R-01: contracts v2 — rendered formats need media_assets.qa_status='pass' for this revision
        if media_qa != "pass":
            F.append(finding("R-01", "format", "blocker",
                             f"RenderQA not passed (media_assets.qa_status={media_qa or 'missing'}); carousel not rendered yet",
                             suggestion="PackageBuilder renders slides (RTL for HE), RenderQA checks count/dims/text-match, then re-run."))

    # CTA (code-checkable parts)
    cta_text = piece.get("cta") or closing
    if "?" not in (cta_text or "") and "?" not in closing:
        F.append(finding("CTA-01", "cta", "major", "no closing question"))
    if re.match(checks["CTA-02"]["params"]["regex"], norm(cta_text).lower()):
        F.append(finding("CTA-02", "cta", "major", "generic CTA", excerpt=cta_text, points_delta=0))
    rb = re.compile(checks["CTA-03"]["params"]["regex"], re.I)
    for field, v in text_fields(piece):
        m = rb.search(v)
        if m:
            F.append(finding("CTA-03", "cta", "major", "engagement bait", field=field, excerpt=m.group(0), points_delta=-10))
    bv = ctx["brand_voice"]
    soft = norm(bv.get(f"cta_primary_{lang}") or "")[:40]
    if soft and soft in norm(closing) and "?" not in closing:
        F.append(finding("CTA-05", "cta", "major", "soft offer replaces the closing question (use it as a P.S. after the question)"))

    # L-05 twin numbers
    if twin is not None:
        num = lambda s: set(re.findall(r"(?<![A-Za-z\d])\d[\d,.]*\+?", s or ""))
        a, b = num(txt), num(all_text(twin))
        if a != b:
            F.append(finding("L-05", "fact", "major", f"numbers differ from twin: this={sorted(a)} twin={sorted(b)}"))
        if sorted(piece.get("fact_ids") or []) != sorted(twin.get("fact_ids") or []):
            F.append(finding("L-05", "fact", "major", "fact_ids differ from twin"))

    blocked = any(f["severity"] == "blocker" for f in F)
    return {"pass": not blocked, "verdict": "block" if blocked else "pass",
            "checklist_version": ctx["checklist"]["version"], "format_spec_id": (spec or {}).get("id"),
            "findings": F}
