"""Shared font resolution for local renderers.

Render machines differ, so no renderer may depend on one hardcoded font path.
Resolution order per renderer:
1. Its explicit environment variable. When set, the path must exist and cover
   the required glyphs: a wrong override fails loudly instead of silently
   changing rendered bytes or dropping characters.
2. The locked template font (kept first so output stays byte-stable on the
   machine where the template was tuned).
3. Common system Hebrew fonts.
Every candidate is checked for glyph coverage of the carousel character set
(Hebrew including final forms, Latin, digits, basic punctuation). A font that
lacks them renders tofu boxes while still passing a naive file-exists check -
NotoSansHebrew from the Debian package, for example, has no Latin or
punctuation glyphs. Coverage is verified with fontTools. Missing fontTools blocks rendering.
Each renderer also checks the actual slide text before drawing.
When nothing resolves, the error lists every path tried and why it failed.
"""
from __future__ import annotations

import os
from pathlib import Path

REQUIRED_CODEPOINTS = frozenset(
    ord(c)
    for c in (
        "אבגדהוזחטיכלמנסעפצקרשתםןץףך"  # Hebrew incl. final forms
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        "0123456789"
        " .,:'\"-?!()—–״׳“”‘’…←→"
    )
)

# Hebrew-capable fonts commonly present on Linux desktops/CI. Coverage is
# verified per machine, so order expresses preference, not assumption.
COMMON_HEBREW_FONTS = [
    "/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansHebrew-Regular.otf",
    "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/droid/DroidSansHebrew-Regular.ttf",
    "/usr/share/fonts/truetype/noto/NotoSerifHebrew-Regular.ttf",
]


def _codepoints(text: str) -> frozenset[int]:
    # Line breaks and tabs control layout rather than selecting visible glyphs.
    return frozenset(ord(c) for c in text if c not in "\n\r\t")


def _font_cmap(path: str) -> set[int]:
    try:
        from fontTools.ttLib import TTCollection, TTFont
    except ImportError as exc:
        raise RuntimeError("fontTools is required for glyph verification; install requirements.txt") from exc
    try:
        if path.lower().endswith(".ttc"):
            with TTCollection(path, lazy=True) as collection:
                return set(collection.fonts[0].getBestCmap() or {})
        with TTFont(path, fontNumber=0, lazy=True) as font:
            return set(font.getBestCmap() or {})
    except Exception as exc:
        raise ValueError(f"Cannot inspect font {path!r}: {exc}") from exc


def _covers_required(path: str) -> bool:
    try:
        return REQUIRED_CODEPOINTS <= _font_cmap(path)
    except (OSError, ValueError):
        return False


def require_glyphs(path: str, text: str) -> None:
    """Fail before drawing if the selected font cannot render actual slide text."""
    missing = (REQUIRED_CODEPOINTS | _codepoints(text)) - _font_cmap(path)
    if missing:
        labels = ", ".join(f"U+{cp:04X}" for cp in sorted(missing))
        raise ValueError(f"Font {path!r} is missing glyphs: {labels}")


def resolve_font(env_var: str, *candidates: str) -> str:
    override = os.environ.get(env_var, "").strip()
    if override:
        if not Path(override).is_file():
            raise FileNotFoundError(
                f"{env_var}={override!r} does not exist. "
                "Point it at a Hebrew-capable .ttf on this machine."
            )
        if not _covers_required(override):
            raise FileNotFoundError(
                f"{env_var}={override!r} does not cover the carousel character set "
                "(Hebrew, Latin, digits, basic punctuation). Choose a fuller font."
            )
        return override
    rejected: list[str] = []
    for path in candidates:
        if not Path(path).is_file():
            rejected.append(f"  - {path} (not installed)")
        elif not _covers_required(path):
            rejected.append(f"  - {path} (missing required glyphs)")
        else:
            return path
    tried = "\n".join(rejected)
    raise FileNotFoundError(
        f"No usable Hebrew font found. Tried:\n{tried}\n"
        f"Install one of these fonts or set {env_var} to a Hebrew-capable .ttf path."
    )
