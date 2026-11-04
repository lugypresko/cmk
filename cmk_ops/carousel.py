"""CarouselBuilder + RenderQA (PIL only, deterministic local template). G1, G12.

text (runs/001-human-gates/carousel_he.md, Variant B) -> 1080x1350 PNG slides -> one PDF.
HE RTL shaping via Pillow + libraqm (direction='rtl'). Same input => same bytes (fixed PDF dates).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, features

W, H = 1080, 1350
MARGIN = 96            # safe area
BAND = 40              # outer band must stay empty (cutoff heuristic)
FONT = "/usr/share/fonts/truetype/sand-box/google/Heebo/Heebo-VariableFont_wght.ttf"
PAPER, INK, LIME, SOFT = (244, 240, 230), (42, 40, 34), (216, 240, 0), (110, 106, 91)
TEMPLATE_ID = "cmk.carousel.he.paper-v0"
FIXED_DATE = "D:20261104000000+02'00'"


def _font(size: int, weight: str):
    f = ImageFont.truetype(FONT, size, layout_engine=ImageFont.Layout.RAQM)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def _wrap(text: str, font, width: int) -> list[str]:
    lines, cur = [], ""
    for w in text.split():
        t = (cur + " " + w).strip()
        if font.getlength(t, direction="rtl") <= width or not cur:
            cur = t
        else:
            lines.append(cur); cur = w
    if cur:
        lines.append(cur)
    return lines


def template_sha(scale: float) -> str:
    spec = {"id": TEMPLATE_ID, "W": W, "H": H, "margin": MARGIN, "font": Path(FONT).name,
            "palette": [PAPER, INK, LIME, SOFT], "scale": scale}
    return hashlib.sha256(json.dumps(spec, sort_keys=True).encode()).hexdigest()


def layout(slide: dict, total: int, scale: float = 1.0) -> dict:
    cover = slide["n"] == 1
    hs, ts = int((84 if cover else 68) * scale), int(44 * scale)
    hf, tf = _font(hs, "Bold"), _font(ts, "Regular")
    box_w = W - 2 * MARGIN
    hl = _wrap(slide["headline"], hf, box_w)
    tl = _wrap(slide.get("text") or "", tf, box_w)
    hlh, tlh = int(hs * 1.25), int(ts * 1.45)
    top = MARGIN + 120                      # below counter + accent bar
    bottom_limit = H - MARGIN - 60          # footer zone
    y_end = top + len(hl) * hlh + 48 + len(tl) * tlh
    return {"hf": hf, "tf": tf, "hs": hs, "ts": ts, "hl": hl, "tl": tl, "hlh": hlh, "tlh": tlh,
            "top": top, "y_end": y_end, "bottom_limit": bottom_limit, "box_w": box_w, "cover": cover}


def draw_slide(slide: dict, total: int, scale: float = 1.0) -> tuple[Image.Image, dict]:
    L = layout(slide, total, scale)
    im = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(im)
    right = W - MARGIN
    d.rectangle([right - 140, MARGIN, right, MARGIN + 14], fill=LIME)                 # accent bar (inside safe area)
    d.text((MARGIN, MARGIN), f"{slide['n']}/{total}", font=_font(30, "Regular"), fill=SOFT, anchor="la")
    y = L["top"]
    for ln in L["hl"]:
        d.text((right, y), ln, font=L["hf"], fill=INK, anchor="ra", direction="rtl"); y += L["hlh"]
    y += 48
    for ln in L["tl"]:
        d.text((right, y), ln, font=L["tf"], fill=INK, anchor="ra", direction="rtl"); y += L["tlh"]
    return im, L


def render(slides: list[dict], out_dir: Path, scale: float = 1.0) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    total = len(slides)
    pages, layouts, pngs = [], [], []
    for s in slides:
        im, L = draw_slide(s, total, scale)
        p = out_dir / f"slide_{s['n']:02d}.png"
        im.save(p, optimize=False)
        pages.append(im); layouts.append(L); pngs.append(p)
    pdf = out_dir / "carousel_he.pdf"
    pages[0].save(pdf, "PDF", save_all=True, append_images=pages[1:], resolution=72.0,
                  title="run001 carousel HE", author="CMK CarouselBuilder", producer="cmk_ops",
                  creator="cmk_ops", creationDate=FIXED_DATE, modDate=FIXED_DATE)
    return {"pdf": pdf, "pngs": pngs, "layouts": layouts}


# ------------------------------------------------------------------ RenderQA
def _ink_in_band(im: Image.Image) -> bool:
    px = im.load()
    for y in list(range(0, BAND)) + list(range(H - BAND, H)):
        for x in range(0, W, 4):
            if px[x, y] != PAPER:
                return True
    for x in list(range(0, BAND)) + list(range(W - BAND, W)):
        for y in range(0, H, 4):
            if px[x, y] != PAPER:
                return True
    return False


def _text_bbox(im: Image.Image, top: int):
    crop = im.crop((0, top, W, H))
    bg = Image.new("RGB", crop.size, PAPER)
    from PIL import ImageChops
    return ImageChops.difference(crop, bg).getbbox()


def qa(slides: list[dict], result: dict, scale: float) -> dict:
    checks, fails, warns = [], 0, 0

    def add(cid, sev, ok, msg, slide=None):
        nonlocal fails, warns
        checks.append({"check_id": cid, "severity": sev, "ok": ok, "slide": slide, "message": msg})
        if not ok:
            fails += sev == "fail"; warns += sev == "warn"

    add("RQ-00", "fail", features.check("raqm"), "libraqm available (HE shaping + bidi)")
    add("RQ-01", "fail", len(result["pngs"]) == len(slides), f"{len(result['pngs'])} pages for {len(slides)} slides")
    for s, p, L in zip(slides, result["pngs"], result["layouts"]):
        im = Image.open(p).convert("RGB")
        n = s["n"]
        add("RQ-02", "fail", im.size == (W, H), f"size {im.size} (want {W}x{H}, 4:5)", n)
        add("RQ-03", "fail", L["y_end"] <= L["bottom_limit"],
            f"text bottom {L['y_end']}px vs limit {L['bottom_limit']}px (cutoff/overflow)", n)
        add("RQ-04", "fail", not _ink_in_band(im), f"no ink in outer {BAND}px band (crop/cutoff)", n)
        bb = _text_bbox(im, L["top"])
        rtl_ok = bool(bb) and abs((W - MARGIN) - bb[2]) <= 12
        add("RQ-05", "fail", rtl_ok, f"RTL right-aligned: ink right edge {bb[2] if bb else None} vs {W - MARGIN}", n)
        add("RQ-06", "fail", L["ts"] >= 32 and L["hs"] >= 48, f"legibility font px headline={L['hs']} text={L['ts']}", n)
        add("RQ-07", "warn", len(s["headline"]) <= (50 if n == 1 else 80), f"headline {len(s['headline'])} chars (F-C3/F-C4)", n)
        add("RQ-08", "warn", len(s.get("text") or "") <= 300, f"text {len(s.get('text') or '')} chars <= 300", n)
        words = len((s["headline"] + " " + (s.get("text") or "")).split())
        add("RQ-09", "warn", words <= 30, f"{words} words (house heuristic <=30)", n)
        add("RQ-10", "warn", len(L["hl"]) <= 3, f"headline wraps to {len(L['hl'])} lines", n)
        add("RQ-11", "warn", not s["headline"][:1].isascii() or not s["headline"][:1].isalpha(),
            "HE headline does not start with a Latin token (F-C7)", n)
    status = "fail" if fails else "pass"
    fix = None
    if fails:
        bad = sorted({c["slide"] for c in checks if not c["ok"] and c["severity"] == "fail" and c["slide"]})
        fix = {"owner": "Itay", "status": "proposed", "apply": "human-only (G12)",
               "proposal": [f"slide {n}: shorten text or re-render at scale 1.0 (current {scale})" for n in bad]
                           or ["environment: install libraqm / fix renderer"]}
    return {"qa_version": "renderqa-v0", "status": status, "failures": fails, "warnings": warns,
            "template_id": TEMPLATE_ID, "template_sha256": template_sha(scale), "scale": scale,
            "checks": checks, "fix_proposal": fix}
