"""EditorialGuardian v0 — HEURISTIC STUB SCORER (keywords + structure, no LLM call).

Production EditorialGuardian (D1) will call an LLM with brand_voice, icp_profiles,
exemplars and the rubric in guardian_rules.md §2–§3, and return the same fields.
This stub exists to calibrate the pipeline and report shape. Its scores are
proxies: treat them as "does the text contain the expected signals", not as
editorial judgment. It NEVER overrides SpecGate/FactGate: report.py applies the
code-gate verdict first and caps brand_score at brand_cap_when_blocked.

Rubric ids follow guardian_checklist.json (BR-1..BR-9, ICP-1..ICP-6, V-01..V-05, ICP-P1/P2).
"""
from __future__ import annotations

import re

from .common import all_text, finding, norm, paragraphs, sentences

SCORER = "heuristic-stub-v0"

KW = {
    "evidence": {"en": [r"I keep hearing", r"I hear", r"I see", r"that's the evidence", r"before naming", r"before giving it a name",
                        r"\bPR\b", r"pull request", r"Slack", r"sync", r"review", r"one last look"],
                 "he": [r"אני שומע", r"שוב ושוב", r"אלה העובדות", r"לפני שנותנים לזה שם", r"PR", r"סלאק", r"סינק", r"סקירה", r"מבט (ה)?אחרון"]},
    "diagnosis_label": {"en": [r"bottleneck"], "he": [r"צוואר בקבוק"]},
    "pattern": {"en": [r"\bpattern\b", r"\bflow\b", r"\bprocess\b", r"\bgates?\b", r"\bchecks?\b", r"\bsystem\b", r"decision dependency"],
                "he": [r"דפוס", r"תהליך", r"שערים?", r"בדיקות", r"מערכת"]},
    "person_flaw": {"en": [r"\b(lack of|no) confidence\b", r"micromanag", r"control freak", r"can't let go"],
                    "he": [r"חוסר ביטחון", r"מיקרו.?מנג'מנט", r"לא יודע לשחרר"]},
    "promise": {"en": [r"come(s)? back to you", r"came back to (you|them)", r"right level", r"needs? your judg(e)?ment", r"learned to wait",
                       r"own(s)? the judg(e)?ment", r"where you're needed"],
                "he": [r"חוזרות? אלי(כם|ך|הם)", r"ברמה הנכונה", r"שיקול (ה)?דעת", r"צריכים אתכם"]},
    "ai": {"en": [r"\bAI\b", r"agents?", r"\bLLM\b", r"model"], "he": [r"AI", r"סוכנ", r"LLM", r"מודל"]},
    "human_start": {"en": [r"\bstart\b.{0,40}human|human.{0,40}\bstart\b", r"owns the requirement"], "he": [r"בהתחלה.{0,40}אדם|אדם.{0,20}בהתחלה", r"מחזיק את הדרישה"]},
    "human_end": {"en": [r"\bend\b.{0,40}human|human.{0,40}\bend\b", r"owns the judg"], "he": [r"בסוף.{0,40}אדם|אדם.{0,20}בסוף", r"מחזיק את שיקול הדעת"]},
    "full_autonomy": {"en": [r"straight to prod", r"no human (in|needed)", r"fully autonomous", r"without (any )?review"],
                      "he": [r"ישר לפרודקשן", r"בלי אדם", r"אוטונומי לגמרי"]},
    "move": {"en": [r"this week", r"one move", r"one reversible move", r"\btake one\b", r"try this"],
             "he": [r"לשבוע הזה", r"צעד", r"קחו", r"נסו"]},
    "manager_lens": {"en": [r"your team", r"dev managers?", r"\bmanagers?\b", r"engineering (manager|leader)", r"\bDirector", r"your desk"],
                     "he": [r"הצוות שלכם", r"מנהלי פיתוח", r"המנהל", r"לצוות", r"השולחן שלכם"]},
    "pain": {"en": [r"come(s)? back to you", r"came back to them", r"one last look", r"sync you have to attend", r"has to attend",
                    r"being present", r"calendar", r"keeps coming back", r"escalation", r"stall"],
             "he": [r"חוזרות? אלי", r"מבט (ה)?אחרון", r"חייב להיות בו", r"נוכחות", r"יומן", r"ממשיכה לחזור", r"הסלמה", r"נתקע"]},
    "leadership": {"en": [r"decision", r"judg(e)?ment", r"requirement", r"accountab", r"authority", r"\bowns?\b"],
                   "he": [r"החלט", r"שיקול (ה)?דעת", r"דרישה", r"אחריות", r"סמכות", r"מחזיק"]},
    "company": {"en": [r"B2B", r"SaaS", r"scal(e|ing)", r"R&D", r"growing", r"org\b"], "he": [r"B2B", r"SaaS", r"צמיחה", r"מו\"פ", r"ארגונ"]},
    "company_implied": {"en": [r"your team", r"agents", r"review", r"pipeline"], "he": [r"הצוות", r"סוכנים", r"סקירה", r"פייפליין"]},
    "org_lens": {"en": [r"\bflow\b", r"\bprocess\b", r"design question", r"\bgates?\b", r"in many teams"], "he": [r"תהליך", r"שאלה של תכנון", r"שערים", r"בהרבה צוותים"]},
    "engineer": {"en": [r"\bPR\b", r"lints?", r"tests?", r"\bCI\b", r"pipeline", r"pull request"], "he": [r"PR", r"לינטר", r"טסט", r"CI", r"פייפליין"]},
    "ic_only": {"en": [r"^(devs|engineers|developers)[:,]", r"\bmy (claude|gpt) prompt\b"], "he": [r"^מפתחים[:,]"]},
    "founder_only": {"en": [r"as a (solo )?founder", r"fellow founders"], "he": [r"כמייסד", r"מייסדים יקרים"]},
    "hype": {"en": [r"10x", r"crush it", r"game[- ]?changer", r"revolutionary", r"hustle"], "he": [r"מהפכני", r"מטורף"]},
    "ai_tells": {"en": [r"in today's fast-paced", r"let's dive in", r"\bunlock\b", r"\bdelve\b", r"in the ever-evolving"], "he": []},
}


def _hits(key: str, lang: str, text: str) -> list[str]:
    out = []
    for pat in KW[key].get(lang, []):
        m = re.search(pat, text, re.I | re.M)
        if m:
            out.append(m.group(0))
    return out


def _dupes(text: str) -> list[str]:
    """Clause-level near-duplicates: same 5-word tail in two clauses (>=5 words).
    Questions are skipped (a CTA that echoes an earlier line is intentional)."""
    seen, d = {}, []
    for s in sentences(text):
        if s.rstrip().endswith("?"):
            continue
        for cl in re.split(r"\s[—–-]\s|[,;]\s", s):
            words = re.sub(r"[^\w\u0590-\u05FF ]", "", norm(cl).lower()).split()
            if len(words) < 5:
                continue
            k = " ".join(words[-5:])
            if k in seen and seen[k] != s:
                d.append(s)
            seen.setdefault(k, s)
    return d


def score(piece: dict, ctx: dict, spec_report: dict | None = None, fact_report: dict | None = None) -> dict:
    lang = piece.get("language", "en")
    text = all_text(piece)
    body = piece.get("body") or ""
    F: list[dict] = []
    comp: dict[str, dict] = {}
    bv = ctx["brand_voice"]

    def put(cid, pts, mx, why):
        comp[cid] = {"points": int(pts), "max": mx, "why": why}

    # BR-1 evidence before diagnosis
    ev = _hits("evidence", lang, text)
    dl = _hits("diagnosis_label", lang, text)
    first_ev = min([text.find(h) for h in ev if text.find(h) >= 0] or [len(text)])
    first_dl = min([text.lower().find(h.lower()) for h in dl] or [len(text) + 1])
    if dl and first_dl < first_ev:
        put("BR-1", 3, 15, f"diagnosis label {dl} before evidence"); F.append(finding("V-06", "voice", "major", "diagnosis label before evidence", points_delta=0))
    else:
        put("BR-1", 15 if len(ev) >= 3 else 8 if ev else 0, 15, f"evidence/scene markers: {ev[:5]}")
    # BR-2 system not person
    pat, flaw = _hits("pattern", lang, text), _hits("person_flaw", lang, text)
    put("BR-2", (10 if len(pat) >= 2 else 5 if pat else 0) - (5 if flaw else 0), 10, f"pattern words {pat[:5]}; person-flaw {flaw}")
    # BR-3 promise alignment (+ say_phrases; HE seeds are needs_review → meaning, not verbatim: L-04)
    pr = _hits("promise", lang, text)
    say = [p for p in (bv.get("say_phrases") or []) if lang == "en" and p.lower() in text.lower()]
    n = len(set(pr)) + len(say)
    put("BR-3", 15 if n >= 3 else 10 if n == 2 else 5 if n == 1 else 0, 15, f"promise markers {pr[:5]}; say_phrases {say[:4]}")
    # BR-4 human at start and end
    if _hits("ai", lang, text):
        hs, he_ = _hits("human_start", lang, text), _hits("human_end", lang, text)
        put("BR-4", 5 * bool(hs) + 5 * bool(he_), 10, f"AI present; human start={bool(hs)} end={bool(he_)}")
    else:
        put("BR-4", 10 if _hits("leadership", lang, text) else 5, 10, "no AI; decision ownership check")
    # BR-5 evidence + numbers, traceable
    matched = [c for c in (fact_report or {}).get("claims", []) if c.get("status") in ("matched", "weaker_ok")]
    put("BR-5", 15 if matched else 8 if len(ev) >= 2 else 0, 15,
        "approved fact used" if matched else "concrete but number-free (no approved facts used)" if ev else "opinion only")
    # BR-6 one reversible move
    mv = _hits("move", lang, text)
    put("BR-6", 10 if len(mv) >= 2 else 6 if mv else 0, 10, f"move markers {mv}")
    # BR-7 practitioner tone (penalties below)
    put("BR-7", 10, 10, "start at 10; hype/cliché/exclamation penalties applied separately")
    # BR-8 CTA
    paras = paragraphs(body)
    closing = piece.get("cta") or (paras[-1] if paras else "")
    if "?" not in (closing or ""):
        put("BR-8", 0, 10, "no closing question")
    elif re.match(r"^(thoughts|agree|what do you think|מה דעתכם)\??$", norm(closing).lower()):
        put("BR-8", 0, 10, "generic CTA")
    else:
        spec_words = len(closing.split())
        own = bool(re.search(r"your team|your flow|in your|שלכם|אצלכם", closing, re.I))
        put("BR-8", 10 if (spec_words >= 8 and own) else 5, 10, f"closing question ({spec_words} words, reader's own team={own})")
    # BR-9 language craft (stub: duplicate sentences, mixed spelling)
    dup = _dupes(body)
    l02 = any(f["check_id"] == "L-02" for f in (spec_report or {}).get("findings", []))
    pts9 = 5 - 2 * min(2, len(dup)) - (1 if l02 else 0)
    put("BR-9", max(0, pts9), 5, f"duplicate sentences {len(dup)}; calque detection needs LLM")
    for d in dup:
        F.append(finding("E-DUP", "voice", "major", "near-duplicate sentence (same idea said twice)", excerpt=d,
                         suggestion="Keep one of the two 'same desk' sentences."))

    brand = sum(c["points"] for c in comp.values())
    pen = 0
    for p in bv.get("avoid_phrases") or []:
        core = re.sub(r"\s*\(.*\)", "", p).split(" / ")[0]
        if core and lang == "en" and core.lower() in text.lower() and core.lower() not in ("pricing or discount claims",
                                                                                           "unapproved client or company names"):
            d = -15 if core.lower() == "just delegate more" else -10
            pen += d; F.append(finding("V-01", "voice", "major", f"avoid_phrase {core!r}", points_delta=d))
    for h in _hits("hype", lang, text):
        pen -= 10; F.append(finding("V-02", "voice", "major", f"hype word {h!r}", points_delta=-10))
    if _hits("ai", lang, text) and _hits("full_autonomy", lang, text):
        pen -= 15; F.append(finding("V-03", "voice", "major", "advocates full autonomy without a human gate", points_delta=-15))
    if text.count("!") > 1:
        pen -= 3; F.append(finding("V-04", "voice", "minor", f"{text.count('!')} exclamation marks", points_delta=-3))
    for h in _hits("ai_tells", lang, text):
        pen -= 5; F.append(finding("V-05", "voice", "minor", f"AI-content tell {h!r}", points_delta=-5))
    for f in (spec_report or {}).get("findings", []):
        if f["check_id"] == "CTA-03":
            pen -= 10
    brand = max(0, min(100, brand + pen))

    # ICP
    icp: dict[str, dict] = {}

    def iput(cid, pts, mx, why):
        icp[cid] = {"points": int(pts), "max": mx, "why": why}

    ml = _hits("manager_lens", lang, text)
    iput("ICP-1", 30 if len(ml) >= 2 else 15 if ml else 0, 30, f"manager-lens markers {ml}")
    pn = _hits("pain", lang, text)
    iput("ICP-2", 25 if len(pn) >= 2 else 15 if pn else 0, 25, f"icp pain markers {pn[:5]}")
    ld = _hits("leadership", lang, text)
    iput("ICP-3", 20 if len(ld) >= 2 else 10 if ld else 5, 20, f"leadership-decision markers {ld[:5]}")
    co, coi = _hits("company", lang, text), _hits("company_implied", lang, text)
    iput("ICP-4", 10 if co else 5 if len(coi) >= 2 else 0, 10, f"explicit {co}; implied {coi[:3]}")
    ol = _hits("org_lens", lang, text)
    iput("ICP-5", 10 if len(ol) >= 2 else 5 if ol else 0, 10, f"org-design markers {ol[:4]}")
    en_ = _hits("engineer", lang, text)
    iput("ICP-6", 5 if en_ else 0, 5, f"engineer-readable tokens {en_[:4]} (bonus only)")
    icp_score = sum(c["points"] for c in icp.values())
    if _hits("ic_only", lang, text) and not ml:
        icp_score -= 15; F.append(finding("ICP-P1", "icp", "major", "addressed solely to ICs", points_delta=-15))
    if _hits("founder_only", lang, text):
        icp_score -= 10; F.append(finding("ICP-P2", "icp", "major", "founder/CEO-only framing", points_delta=-10))
    icp_score = max(0, min(100, icp_score))
    if lang == "he":
        F.append(finding("L-04", "language", "info", "HE brand_voice/icp seeds needs_review=true: HE say_phrases not required verbatim"))

    th = ctx["thresholds"]
    return {
        "scorer": SCORER,
        "note": "Heuristic stub for calibration only. Production EditorialGuardian calls an LLM with the guardian_rules.md rubric.",
        "brand_score": brand, "icp_relevance_score": icp_score,
        "brand_components": comp, "icp_components": icp, "penalties": pen,
        "source_supports_wording": "n_a" if not matched else "yes",
        "adds_value": bool(mv) and bool(pat),
        "misleading_risk": "none detected by heuristics (LLM review pending)",
        "recommend_reject": brand < th["reject_brand_below"] or icp_score < th["reject_icp_below"],
        "findings": F,
    }
