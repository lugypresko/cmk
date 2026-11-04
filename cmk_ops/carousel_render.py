"""Deterministic HE LinkedIn carousel → PNG slides + multi-page PDF + RenderQA."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 1350  # LinkedIn portrait carousel
MARGIN = 72
TITLE_SIZE = 54
BODY_SIZE = 36
MAX_TITLE_CHARS = 50
MAX_BODY_WORDS = 40
FONT_REG = "/usr/share/fonts/truetype/sand-box/google/IBM Plex Sans Hebrew/IBMPlexSansHebrew-Regular.ttf"
FONT_BOLD = FONT_REG  # bold variant may be absent; regular is fine for v0
BG = (15, 23, 42)
FG = (248, 250, 252)
MUTED = (148, 163, 184)
ACCENT = (56, 189, 248)

SLIDES_VARIANT_B = [
    ("יותר תפוקת AI. אותן החלטות על השולחן שלכם.",
     "איפה האדם יושב בתהליך חשוב יותר מאיזה מודל אתם מריצים."),
    ("בדקו איפה אתם יושבים היום",
     "עוברים על שלבי ביניים. מאשרים טיוטות. עונים \"זה בסדר?\" בסלאק. האחריות הפכה בשקט לנוכחות."),
    ("בהתחלה: אדם מחזיק את הדרישה",
     "מה פותרים. איך נראה \"גמור\". מה אסור שיישבר."),
    ("באמצע: שערים דטרמיניסטיים",
     "לינטרים, טסטים, צ'קליסט עם רף ברור. אותה תשובה בכל פעם."),
    ("בסוף: אדם מחזיק את שיקול הדעת",
     "לא \"זה עבר?\". השאלה היא \"זה הדבר הנכון, ומשחררים?\"."),
    ("כלל או שיקול דעת?",
     "אם בדיקה נותנת אותה תשובה לכל מי שבודק — כלל לשער. אם צריך הקשר שרק לכם יש — שיקול דעת בסוף."),
    ("צעד לשבוע הזה",
     "קחו סקירה שחוזרת אליכם. סמנו כל סעיף: כלל או שיקול דעת. כללים לשער, שיקול דעת לסוף."),
    ("איפה יושב האדם בתהליך שלכם?",
     "בהתחלה ובסוף, או באמצע של כל שלב?"),
]


def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_REG, size)


def _wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur: list[str] = []
    for w in words:
        trial = " ".join(cur + [w])
        if draw.textlength(trial, font=font) <= max_w:
            cur.append(w)
        else:
            if cur:
                lines.append(" ".join(cur))
            cur = [w]
    if cur:
        lines.append(" ".join(cur))
    return lines or [""]


def render_slide(idx: int, title: str, body: str, out: Path) -> Path:
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    title_f = _font(TITLE_SIZE)
    body_f = _font(BODY_SIZE)
    small = _font(28)
    max_w = W - 2 * MARGIN
    # RTL: draw right-aligned
    y = MARGIN + 40
    draw.text((W - MARGIN, y), f"{idx}/8", font=small, fill=MUTED, anchor="ra")
    y += 80
    for line in _wrap(draw, title, title_f, max_w):
        draw.text((W - MARGIN, y), line, font=title_f, fill=FG, anchor="ra")
        y += TITLE_SIZE + 12
    y += 36
    draw.rectangle((MARGIN, y, W - MARGIN, y + 4), fill=ACCENT)
    y += 40
    for line in _wrap(draw, body, body_f, max_w):
        draw.text((W - MARGIN, y), line, font=body_f, fill=MUTED, anchor="ra")
        y += BODY_SIZE + 14
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG")
    return out


def render_qa(title: str, body: str, img_path: Path) -> list[dict]:
    issues = []
    if len(title) > MAX_TITLE_CHARS:
        issues.append({"check": "title_len", "severity": "warn", "detail": f"title {len(title)}>{MAX_TITLE_CHARS}"})
    words = len(body.split())
    if words > MAX_BODY_WORDS:
        issues.append({"check": "body_words", "severity": "warn", "detail": f"body {words}>{MAX_BODY_WORDS} words"})
    # heuristic: Hebrew present
    if not re.search(r"[\u0590-\u05FF]", title + body):
        issues.append({"check": "he_script", "severity": "block", "detail": "missing Hebrew characters"})
    img = Image.open(img_path)
    if img.size != (W, H):
        issues.append({"check": "dims", "severity": "block", "detail": f"got {img.size}"})
    # bottom margin: sample last 40 rows shouldn't be empty of content always — skip deep OCR
    return issues


def build_variant_b(out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    slides_meta = []
    pngs = []
    all_issues = []
    for i, (title, body) in enumerate(SLIDES_VARIANT_B, 1):
        png = out_dir / f"slide_{i:02d}.png"
        render_slide(i, title, body, png)
        issues = render_qa(title, body, png)
        sha = hashlib.sha256(png.read_bytes()).hexdigest()
        slides_meta.append({"n": i, "title": title, "body": body, "path": str(png), "sha256": sha, "qa": issues})
        pngs.append(png)
        all_issues.extend([{**x, "slide": i} for x in issues])
    pdf = out_dir / "carousel_he_variant_b.pdf"
    images = [Image.open(p).convert("RGB") for p in pngs]
    images[0].save(pdf, save_all=True, append_images=images[1:])
    pdf_sha = hashlib.sha256(pdf.read_bytes()).hexdigest()
    blocking = [x for x in all_issues if x.get("severity") == "block"]
    report = {
        "variant": "B",
        "slide_count": len(slides_meta),
        "pdf": str(pdf),
        "pdf_sha256": pdf_sha,
        "slides": slides_meta,
        "render_qa": {"pass": not blocking, "issues": all_issues, "proposed_fixes": [
            "Shorten titles over 50 chars", "Trim body over 40 words", "Keep Hebrew script"
        ] if all_issues else []},
        "note": "Stripe slide replaced with rule/judgment slide for Variant B (no unapproved fact).",
    }
    (out_dir / "render_qa.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    r = build_variant_b(root / "runs/001-human-gates/out")
    print(json.dumps({"pdf": r["pdf"], "pdf_sha256": r["pdf_sha256"], "qa_pass": r["render_qa"]["pass"], "issues": len(r["render_qa"]["issues"])}, ensure_ascii=False))
