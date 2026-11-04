from cmk_ops.carousel_render import build_variant_b
from pathlib import Path
import json
r = build_variant_b(Path(__file__).resolve().parents[1] / 'runs/001-human-gates/out')
print(json.dumps({'pdf': r['pdf'], 'qa_pass': r['render_qa']['pass']}))
