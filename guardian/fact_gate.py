"""Heuristic claim extraction and literal approved-wording checks, not truth verification.
Word/number overlap only proposes a candidate fact. Nonliteral wording is blocked for
explicit semantic review. Extraction is incomplete; unclassified text is reported for
human review. No model verdict or fact_id alone establishes semantic support.
"""
from __future__ import annotations

import re

from .common import fact_usable, finding, norm, sentences, text_fields

NUM_RE = re.compile(r"(?<![A-Za-z\u0590-\u05FF\d])(\d[\d,.]*)\s*(\+|%|x|×)?(?![A-Za-z\d])")
MULT_RE = re.compile(r"\b\d+(\.\d+)?\s*[x×]\b|\bפי\s+\S+|\b(double|triple|halve)[sd]?\b", re.I)
HE_STRONG_NUM = re.compile(r"(?<![\u0590-\u05FF])(עשר|עשרות|מאה|מאות|אלף|אלפי|מיליון)(?![\u0590-\u05FF])")
CRED_RE = re.compile(r"\b(years? (of|in)|certified|certification|PhD|award|hours of coaching|coaching hours)\b|שנות ניסיון|שעות אימון|מוסמך", re.I)
OUTCOME_RE = re.compile(r"\b(will|would|guaranteed to)\s+(increase|reduce|double|cut|improve|boost|grow)\b|\bships? \w*\s*faster\b|\b\d+% (faster|more|less|fewer)\b|יותר מהר ב|מכפיל", re.I)
EXPERIENCE_RE = re.compile(r"\b(I keep|I hear|I've seen|I see|I talk to|I find|in my experience|I'm running|I run|I coach|what I keep seeing)\b|אני שומע|אני רואה|שאני מדבר|מניסיוני|אני מריץ|ככה אני|שוב ושוב אני", re.I)
GENERAL_RE = re.compile(r"\b(every|all|most|many|always|never|nobody|no one)\b[^.?!]{0,40}\b(teams?|managers?|companies|orgs?|engineers?|leaders?)\b|\b(in many|in most) teams\b|בהרבה צוותים|רוב ה(מנהלים|צוותים|חברות)|כל (המנהלים|הצוותים)", re.I)
# Named third party + an assertion verb about it.
TP_EN = re.compile(r"\b([A-Z][a-zA-Z]+(?:\.[a-z]+)?)\s+(has|have|had|is|are|was|were|uses?|used|built|wrote|written|publish\w*|merg\w*|ships?|shipped|runs?|ran|says?|said|reports?|reported|announced)\b")
TP_HE = re.compile(r"(?:ב-?|ש-?)?([A-Z][a-zA-Z]+)\s+(כתבו|פרסמו|משתמשים|בנו|מריצים|הודיעו|דיווחו|ממזגים)|ב-?([A-Z][a-zA-Z]+)\s+(כתבו|פרסמו|משתמשים|בנו|מריצים|הודיעו|דיווחו|ממזגים)")
HE_ASSERTION_RE = re.compile(r"(?:^|\s)(?:המערכת|החברה|הצוות|המוצר|השירות|אנחנו)\s+(?:לא\s+)?(?:שומרת?|מאחסנת?|תומכת?|מספקת?|מפעילה?|משתמשת?|מייצרת?|מאפשרת?|עובדת?|פועל(?:ת)?)(?:\s|$)|(?:^|\s)(?:הפחתנו|הגדלנו|צמצמנו|שיפרנו|העלינו|הורדנו|השקנו|סיפקנו|ביצענו|חסכנו)(?:\s|$)")
NOT_ENTITIES = {"The", "This", "That", "These", "Those", "It", "I", "We", "You", "Your", "Our", "They", "He", "She", "A", "An",
                "Not", "Start", "Middle", "End", "One", "Same", "Before", "Accountability", "Output", "Gate", "Mark", "List",
                "Take", "Keep", "In", "If", "So", "Then", "Agents", "Agent", "Each", "Every", "Most", "Many", "What", "Who",
                "Where", "When", "Lints", "Gates", "Often", "Some", "Look", "Move", "Turn", "Write", "Bring", "Watch",
                "WHAT", "HOW", "PR", "AI", "LLM", "OK"}
TOKEN = re.compile(r"[\w\u0590-\u05FF]{3,}")
STOP = set("the and for that with this from your you are was were but not have has had its it's our they their them what when where which who will would can could into onto than then also just only very more most some such each every about over under".split())


def _numbers(s: str) -> list[tuple[float, bool]]:
    out = []
    for m in NUM_RE.finditer(s or ""):
        try:
            out.append((float(m.group(1).replace(",", "").rstrip(".")), m.group(2) == "+"))
        except ValueError:
            pass
    return out


def _tokens(s: str) -> set[str]:
    return {t for t in TOKEN.findall((s or "").lower()) if t not in STOP}


def _signals(sent: str) -> list[str]:
    sig = []
    nums = [m for m in NUM_RE.finditer(sent)]
    # ignore list/step ordinals like "1." at line start and "1:1" format token is still a claim
    if nums:
        sig.append("number")
    if "%" in sent:
        sig.append("percent")
    if MULT_RE.search(sent):
        sig.append("multiplier")
    if HE_STRONG_NUM.search(sent):
        sig.append("he_number_word")
    if HE_ASSERTION_RE.search(sent):
        sig.append("he_assertion")
    if CRED_RE.search(sent):
        sig.append("credential")
    if OUTCOME_RE.search(sent):
        sig.append("outcome")
    ents = [m.group(1) for m in TP_EN.finditer(sent) if m.group(1) not in NOT_ENTITIES]
    for m in TP_HE.finditer(sent):
        e = m.group(1) or m.group(3)
        if e and e not in NOT_ENTITIES:
            ents.append(e)
    if ents:
        sig.append("third_party:" + ",".join(sorted(set(ents))))
    return sig


def extract_claims(piece: dict) -> list[dict]:
    claims, seen = [], set()
    for field, text in text_fields(piece):
        for s in sentences(text):
            key = s.strip()
            if key in seen:
                continue
            sig = _signals(s)
            exp = bool(EXPERIENCE_RE.search(s))
            gen = bool(GENERAL_RE.search(s))
            if s.rstrip().endswith("?") and not sig:
                continue  # question => opinion, not emitted
            if sig:
                kind = "fact"  # quantified experience is still a fact (C-05)
            elif exp or gen:
                kind = "experience"
            else:
                continue
            seen.add(key)
            claims.append({"text": s, "field": field, "kind": kind, "signals": sig + (["experience_marker"] if exp else []) + (["generalisation"] if gen else [])})
    return claims


def _literal(s: str) -> str:
    # Preserve words, negation, direction, signs and internal punctuation.
    return norm(s).casefold().rstrip(".?!; ")


def _literal_support(text: str, fact: dict) -> bool:
    return any(_literal(text) == _literal(fact.get(k) or "")
               for k in ("statement_en", "statement_he") if fact.get(k))


def _match(claim: dict, facts: list[dict], lang: str) -> tuple[dict | None, float]:
    best, best_score = None, 0.0
    ct = _tokens(claim["text"])
    cn = [n for n, _ in _numbers(claim["text"])]
    for f in facts:
        if _literal_support(claim["text"], f):
            return f, 10.0
        stmt = f"{f['statement_en']} {f['statement_he']}"
        ft = _tokens(stmt) | set(f["fact_key"].replace(".", " ").replace("_", " ").lower().split())
        fn = [n for n, _ in _numbers(stmt)]
        score = len(ct & ft) / max(1, min(len(ct), 8))
        if cn and fn and set(cn) & set(fn):
            score += 0.5
        ents = [x.split(":", 1)[1] for x in claim.get("signals", []) if x.startswith("third_party:")]
        for e in ents:
            for name in e.split(","):
                if name.lower() in f["fact_key"].lower() or name.lower() in stmt.lower():
                    score += 0.6
        if score > best_score:
            best, best_score = f, score
    return (best, best_score) if best_score >= 0.6 else (None, best_score)


def _compare_numbers(claim_text: str, fact: dict) -> str:
    cn = _numbers(claim_text)
    fn = _numbers(f"{fact['statement_en']} {fact['statement_he']}")
    if not cn:
        return "matched"
    if not fn:
        return "stronger_fail"
    status = "matched"
    for n, _plus in cn:
        cands = [(v, p) for v, p in fn]
        if any(v == n for v, _ in cands):
            continue
        # weaker is OK only against a floor ("25+" → "over 20"); bigger than every floor fails
        if any(p and n < v for v, p in cands) or any(n < v for v, _ in cands):
            status = "weaker_ok"
        else:
            return "stronger_fail"
    return status


def check(piece: dict, facts: list[dict], claims: list[dict] | None = None) -> dict:
    F: list[dict] = []
    lang = piece.get("language", "en")
    usable_ids, by_id = set(), {}
    for f in facts:
        ok, why = fact_usable(f)
        f["_usable"], f["_why"] = ok, why
        by_id[str(f["id"])] = f
        if ok:
            usable_ids.add(str(f["id"]))
    listed = [str(x) for x in (piece.get("fact_ids") or [])]

    # B-08: listed fact_ids must be usable
    for fid in listed:
        f = by_id.get(fid)
        if f is None:
            F.append(finding("B-08", "fact", "blocker", f"fact_id {fid} not found in facts", field="fact_ids"))
        elif not f["_usable"]:
            F.append(finding("B-08", "fact", "blocker", f"fact_id {fid} ({f['fact_key']}) not usable: {f['_why']}", field="fact_ids"))

    extracted = claims if claims is not None else extract_claims(piece)
    out_claims, unsupported = [], []
    for c in extracted:
        c = dict(c)
        c.setdefault("signals", [])
        if c.get("kind") in ("experience", "opinion"):
            c.update(fact_id=None, status=None)
            out_claims.append(c)
            continue
        fact = by_id.get(str(c.get("fact_id"))) if c.get("fact_id") else None
        if fact is None:
            fact, _ = _match(c, facts, lang)
        if fact is None:
            c.update(fact_id=None, status="missing", reason="no fact row matches this claim")
        elif not fact["_usable"]:
            st = "expired" if fact["_why"].startswith("expired") else "missing"
            c.update(fact_id=str(fact["id"]), fact_key=fact["fact_key"], status=st,
                     reason=f"closest fact {fact['fact_key']} is not usable ({fact['_why']})")
        else:
            st = _compare_numbers(c["text"], fact)
            if st != "stronger_fail" and not _literal_support(c["text"], fact):
                st = "semantic_review_required"
                c["reason"] = "word/number overlap is only a candidate; nonliteral wording needs explicit support review"
            c["support_basis"] = "literal_approved_wording" if st == "matched" else "unverified_candidate"
            c.update(fact_id=str(fact["id"]), fact_key=fact["fact_key"], status=st)
            if st != "stronger_fail" and str(fact["id"]) not in listed:
                c["status"] = "missing"
                c["reason"] = f"matches usable fact {fact['fact_key']} but it is not listed in fact_ids"
        if c["status"] in ("missing", "expired", "stronger_fail", "semantic_review_required"):
            unsupported.append(c["text"])
            F.append(finding("B-01", "fact", "blocker", f"unsupported claim ({c['status']}): {c.get('reason', 'number stronger than fact')}",
                             field=c.get("field"), excerpt=c["text"],
                             suggestion="Use the exact usable approved wording and list its id, or have a human review the claim and approve a new fact version. No model verdict grants approval."))
        out_claims.append(c)

    # C-04: listed but not used
    for fid in listed:
        if fid in by_id and not any(c.get("fact_id") == fid for c in out_claims):
            F.append(finding("C-04", "fact", "minor", f"fact_id {fid} listed but no claim uses it", field="fact_ids"))
    # C-05: quantified experience
    for c in out_claims:
        if c["kind"] == "fact" and "experience_marker" in c["signals"] and any(s in c["signals"] for s in ("number", "percent")):
            F.append(finding("C-05", "fact", "major", "quantified experience generalisation is treated as a fact", excerpt=c["text"]))
    for k in piece.get("pending_fact_keys") or []:
        F.append(finding("C-08", "fact", "info", f"pending_fact_keys lists {k} (not approved; the text in this variant must not rely on it)"))

    emitted = {c["text"].strip() for c in out_claims}
    unclassified = [{"field": field, "text": sentence}
                    for field, text in text_fields(piece) for sentence in sentences(text)
                    if sentence.strip() and sentence.strip() not in emitted and not sentence.rstrip().endswith("?")]
    if unclassified:
        F.append(finding("B-01", "fact", "info", "Claim extraction is incomplete: unclassified text requires human factual/semantic review; a deterministic pass is not evidence of support."))
    blocked = any(f["severity"] == "blocker" for f in F)
    return {"pass": not blocked, "verdict": "block" if blocked else "pass", "claims": out_claims,
            "unsupported_claims": unsupported, "findings": F,
            "review": {"extraction": "heuristic_incomplete", "semantic_support": "not_verified",
                       "human_review_required": bool(out_claims or unclassified),
                       "unclassified_sentences": unclassified,
                       "note": "Pass means no implemented deterministic blocker; it is not factual or semantic approval."},
            "facts_considered": {"total": len(facts), "usable": len(usable_ids),
                                 "statuses": sorted({f["status"] for f in facts})}}
