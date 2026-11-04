"""Regression coverage for readiness font verification, without rendering approvals."""
import builtins
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from . import fonts


class FontTests(unittest.TestCase):
    def test_missing_fonttools_blocks_even_an_existing_override(self):
        original = builtins.__import__
        def missing(name, *args, **kwargs):
            if name.startswith('fontTools'):
                raise ImportError('simulated missing dependency')
            return original(name, *args, **kwargs)
        with tempfile.NamedTemporaryFile(suffix='.ttf') as f:
            with patch.dict('os.environ', {'CMK_TEST_FONT': f.name}), patch('builtins.__import__', side_effect=missing):
                with self.assertRaisesRegex(RuntimeError, 'fontTools is required'):
                    fonts.resolve_font('CMK_TEST_FONT', f.name)

    def test_actual_text_includes_characters_outside_baseline(self):
        with patch.object(fonts, '_font_cmap', return_value=set(fonts.REQUIRED_CODEPOINTS)):
            fonts.require_glyphs('fixture.ttf', 'שלום English ״test״ — 123\n')
            with self.assertRaisesRegex(ValueError, r'U\+20AC'):
                fonts.require_glyphs('fixture.ttf', 'מחיר €')

    def test_missing_hebrew_latin_or_punctuation_is_rejected(self):
        for char in ['ך', 'Z', '—', '״']:
            with self.subTest(char=char), patch.object(fonts, '_font_cmap', return_value=set(fonts.REQUIRED_CODEPOINTS)-{ord(char)}):
                self.assertFalse(fonts._covers_required('fixture.ttf'))

    def test_override_does_not_silently_fall_back(self):
        with tempfile.NamedTemporaryFile(suffix='.ttf') as f:
            with patch.dict('os.environ', {'CMK_TEST_FONT': f.name}), patch.object(fonts, '_covers_required', return_value=False):
                with self.assertRaisesRegex(FileNotFoundError, 'does not cover'):
                    fonts.resolve_font('CMK_TEST_FONT', '/fallback.ttf')

    def test_fallback_reports_rejected_candidates(self):
        with patch.dict('os.environ', {'CMK_TEST_FONT': ''}):
            with self.assertRaisesRegex(FileNotFoundError, 'not installed'):
                fonts.resolve_font('CMK_TEST_FONT', '/missing-font-123.ttf')

    def test_real_system_font_covers_bilingual_punctuation(self):
        font=fonts.resolve_font('CMK_TEST_FONT', *fonts.COMMON_HEBREW_FONTS)
        fonts.require_glyphs(font, 'שלום ״צוות״ — Team’s AI → החלטה')

    def test_both_renderers_check_text_before_creating_files(self):
        from . import carousel, carousel_render
        with tempfile.TemporaryDirectory() as d:
            target=Path(d)/'blocked.png'
            with patch.object(carousel_render,'require_glyphs',side_effect=ValueError('missing glyph')):
                with self.assertRaisesRegex(ValueError,'missing glyph'):
                    carousel_render.render_slide(1,'שלום','טקסט',target)
            self.assertFalse(target.exists())
            with patch.object(carousel,'require_glyphs',side_effect=ValueError('missing glyph')):
                with self.assertRaisesRegex(ValueError,'missing glyph'):
                    carousel.draw_slide({'n':1,'headline':'שלום','text':'טקסט'},8)
