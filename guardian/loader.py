"""Load a piece from the run markdown format (```yaml frontmatter + ```text blocks /
**n — headline** slides / ## sections) or from a ContentPiece / CoreAsset JSON file.

Variants (run 001 convention):
  A  = full text; ⟦STRIPE⟧ / ⟦NEED_APPROVED_FACT⟧ paragraphs kept (marker labels stripped).
  B  = those paragraphs removed; carousel slides with NEED_APPROVED_FACT use the documented fallback.
Any other ⟦...⟧ marker (e.g. ⟦ITAY_CONFIRM⟧) is left in the text for SpecGate S-02.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

VARIANT_MARKERS = re.compile(r"⟦(STRIPE|NEED_APPROVED_FACT)[^⟧]*⟧")


# ---------------------------------------------------------------- mini YAML
def _strip_comment(line: str) -> str:
    out, q, esc = [], None, False
    for i, ch in enumerate(line):
        if esc:
            out.append(ch); esc = False; continue
        if ch == "\\" and q == '"':
            out.append(ch); esc = True; continue
        if ch in "\"'" and (q is None or q == ch):
            q = None if q else ch
        if ch == "#" and q is None and (i == 0 or line[i - 1] in " \t"):
            break
        out.append(ch)
    return "".join(out).rstrip()


def _scalar(v: str):
    v = v.strip()
    if v in ("null", "~", ""):
        return None
    if v in ("true", "false"):
        return v == "true"
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        return [_scalar(x) for x in inner.split(",")] if inner else []
    if v.startswith('"') and v.endswith('"') and len(v) >= 2:
        s = v[1:-1]
        s = re.sub(r'\\+"', '"', s)  # tolerate over-escaped quotes (\\" in run 001 EN)
        return s.replace("\\n", "\n").replace("\\\\", "\\")
    if v.startswith("'") and v.endswith("'"):
        return v[1:-1].replace("''", "'")
    return v


def parse_yaml_block(text: str) -> dict:
    data: dict = {}
    lines = text.splitlines()
    i, key = 0, None
    while i < len(lines):
        raw = lines[i]
        line = _strip_comment(raw)
        i += 1
        if not line.strip():
            continue
        m_item = re.match(r"^\s+-\s+(.*)$", line)
        if m_item and key is not None:
            if not isinstance(data.get(key), list):
                data[key] = []
            data[key].append(_scalar(m_item.group(1)))
            continue
        m = re.match(r"^([A-Za-z_][\w\-]*):\s*(.*)$", line)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        # multi-line double-quoted scalar
        if val.startswith('"') and not re.search(r'(?<!\\)"\s*$', val[1:]):
            buf = [val]
            while i < len(lines):
                nxt = lines[i]; i += 1
                buf.append(nxt)
                if re.search(r'(?<!\\)"\s*(#.*)?$', nxt):
                    break
            val = _strip_comment("\n".join(buf))
        data[key] = _scalar(val) if val != "" else None
    return data


# ---------------------------------------------------------------- markdown sections
def _fenced(md: str, lang: str) -> list[tuple[int, str]]:
    return [(m.start(), m.group(1)) for m in re.finditer(r"```" + lang + r"\n(.*?)```", md, re.S)]


def _sections(md: str) -> dict[str, str]:
    """## heading -> content (until next ## heading). Fenced blocks are skipped for heading detection."""
    out, cur, buf, in_fence = {}, None, [], False
    for line in md.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
        if not in_fence and line.startswith("## "):
            if cur is not None:
                out[cur] = "\n".join(buf).strip()
            cur, buf = line[3:].strip(), []
        else:
            buf.append(line)
    if cur is not None:
        out[cur] = "\n".join(buf).strip()
    return out


def _find(sections: dict, *names: str) -> str | None:
    for n in names:
        for k, v in sections.items():
            if k.lower().startswith(n.lower()):
                return v
    return None


def _text_block(sec: str | None) -> str | None:
    if not sec:
        return None
    m = re.search(r"```text\n(.*?)```", sec, re.S)
    return m.group(1).strip() if m else sec.strip()


def _apply_variant(text: str, variant: str) -> str:
    if variant == "B":
        paras = re.split(r"(\n\s*\n)", text)
        kept = [p for p in paras if not VARIANT_MARKERS.search(p)]
        text = "".join(kept)
        text = re.sub(r"\n{3,}", "\n\n", text)
    else:
        text = VARIANT_MARKERS.sub("", text)
        text = re.sub(r"[ \t]{2,}", " ", text)
    return text.strip()


def _approval(sections: dict) -> dict:
    sec = _find(sections, "Approval", "אישור")
    out = {}
    if sec:
        for m in re.finditer(r"^-\s*(\w+):\s*(.+)$", sec, re.M):
            out[m.group(1)] = m.group(2).strip()
    return out


def _slides(sec: str, variant: str) -> tuple[list[dict], list[str]]:
    slides, notes = [], []
    blocks = re.split(r"(?m)^(?=\*\*\d+\s+—)", sec)
    for b in blocks:
        m = re.match(r"\*\*(\d+)\s+—\s+(.+?)\*\*(.*?)\n(.*)", b, re.S)
        if not m:
            continue
        n, headline, tail, rest = int(m.group(1)), m.group(2).strip(), m.group(3), m.group(4)
        text_lines, fallback = [], None
        for ln in rest.splitlines():
            if ln.startswith(">"):
                fb = re.search(r"\*\*\"?(.+?)\"?\*\*\s*—\s*\S+:\s*\"(.+)\"", ln)
                if fb:
                    fallback = {"headline": fb.group(1).strip('"'), "text": fb.group(2)}
                continue
            if ln.strip():
                text_lines.append(ln.strip())
        text = " ".join(text_lines)
        needs_fact = bool(VARIANT_MARKERS.search(tail + headline))
        if needs_fact and variant == "B":
            if fallback:
                headline, text = fallback["headline"], fallback["text"]
                notes.append(f"slide {n}: variant B fallback used")
            else:
                notes.append(f"slide {n}: variant B, no fallback found; slide dropped")
                continue
        slides.append({"n": n, "headline": VARIANT_MARKERS.sub("", headline).strip(), "text": text})
    return slides, notes


def load_piece(path: str | Path, variant: str = "A") -> dict:
    p = Path(path)
    raw = p.read_text(encoding="utf-8")
    meta = {"source_path": str(p), "source_sha256": hashlib.sha256(raw.encode()).hexdigest(),
            "variant": variant, "loader_notes": []}
    if p.suffix == ".json":
        piece = json.loads(raw)
        piece.setdefault("contract", "cmk/ContentPiece" if "format" in piece else "cmk/CoreAsset")
        piece["_meta"] = meta
        return piece

    yb = _fenced(raw, "yaml")
    fm = parse_yaml_block(yb[0][1]) if yb else {}
    secs = _sections(raw)
    piece = dict(fm)
    piece["_frontmatter_keys"] = sorted(fm.keys())
    contract = fm.get("contract", "cmk/ContentPiece")
    appr = _approval(secs)
    if appr.get("approved_at") and not piece.get("approved_at"):
        piece["approved_at"] = appr["approved_at"]
    if appr:
        meta["approval_section"] = appr

    if contract == "cmk/CoreAsset":
        lang = fm.get("primary_language", "en")
        piece["language"] = lang
        piece["format"] = "core_asset"
        piece["title"] = (_find(secs, "Title", "כותרת") or "").strip()
        piece["thesis"] = (_find(secs, "Thesis", "תזה") or "").strip()
        body = _find(secs, "Body", "גוף") or ""
        piece["body"] = _apply_variant(body, variant)
        kp = _find(secs, "Key points", "נקודות מפתח") or ""
        piece["key_points"] = [re.sub(r"^\d+\.\s*", "", l).strip() for l in kp.splitlines() if re.match(r"^\d+\.", l)]
        cta_sec = _find(secs, "CTA") or ""
        lines = [l.strip() for l in cta_sec.splitlines() if l.strip()]
        piece["cta"] = lines[0] if lines else None
        ps = [l for l in lines[1:] if re.match(r"^\*(P\.S\.|נ\.ב\.)", l)]
        piece["ps"] = re.sub(r"^\*[^*]*\*:?\s*", "", ps[0]) if ps else None
    else:
        fmt = fm.get("format")
        if fmt == "carousel":
            slides_sec = _find(secs, "Slides", "שקפים") or ""
            piece["slides"], notes = _slides(slides_sec, variant)
            meta["loader_notes"] += notes
            piece["body"] = _apply_variant(_text_block(_find(secs, "Caption", "כיתוב")) or "", variant)
        else:
            body = _text_block(_find(secs, "Post text", "טקסט הפוסט"))
            if body is None:
                tb = _fenced(raw, "text")
                body = tb[0][1] if tb else ""
            piece["body"] = _apply_variant(body, variant)
    piece["contract"] = contract
    if variant == "B":
        meta["loader_notes"].append("variant B: paragraphs with ⟦STRIPE⟧/⟦NEED_APPROVED_FACT⟧ removed")
    piece["_meta"] = meta
    return piece
