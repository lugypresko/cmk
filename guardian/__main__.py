"""python -m guardian PIECE [--facts facts.json] [--claims claims.json] [--variant A|B]
                     [--twin OTHER_PIECE] [--media-qa pass|fail|pending] [--strict] [--out report.json]

Exit code: 0 = gates pass, 1 = SpecGate/FactGate block, 2 = usage/load error.
"""
from __future__ import annotations

import argparse
import json
import sys

from . import editorial_guardian, fact_gate, spec_gate
from .common import load_context, load_facts, load_json
from .loader import load_piece
from .report import assemble


def run(piece_path, facts_path=None, claims_path=None, variant="A", twin_path=None, media_qa=None,
        strict=False, fixtures=None) -> dict:
    ctx = load_context(fixtures)
    piece = load_piece(piece_path, variant)
    twin = load_piece(twin_path, variant) if twin_path else None
    facts = load_facts(facts_path)
    claims = load_json(claims_path) if claims_path else None
    spec = spec_gate.check(piece, ctx, strict=strict, media_qa=media_qa, twin=twin)
    fact = fact_gate.check(piece, facts, claims)
    ed = editorial_guardian.score(piece, ctx, spec, fact)
    rep = assemble(piece, spec, fact, ed, ctx)
    rep["inputs"] = {"facts": str(facts_path or "guardian/fixtures/approved_facts_db.json"),
                     "claims": claims_path, "twin": twin_path, "media_qa": media_qa, "strict": strict}
    return rep


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="python -m guardian", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("piece")
    ap.add_argument("--facts")
    ap.add_argument("--claims", help="pre-extracted claims JSON [{text, kind, fact_id?}]")
    ap.add_argument("--variant", choices=["A", "B"], default="A")
    ap.add_argument("--twin")
    ap.add_argument("--media-qa", choices=["pass", "fail", "pending"])
    ap.add_argument("--strict", action="store_true", help="missing DB ids/scores are blockers")
    ap.add_argument("--fixtures")
    ap.add_argument("--out")
    ap.add_argument("--summary", action="store_true", help="print a one-line summary instead of JSON")
    a = ap.parse_args(argv)
    try:
        rep = run(a.piece, a.facts, a.claims, a.variant, a.twin, a.media_qa, a.strict, a.fixtures)
    except (OSError, ValueError, KeyError) as e:
        print(f"guardian: error: {e}", file=sys.stderr)
        return 2
    js = json.dumps(rep, ensure_ascii=False, indent=2)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(js + "\n")
    if a.summary or a.out:
        blk = [f"{f['check_id']}" for f in rep["findings"] if f["severity"] == "blocker"]
        print(f"{rep['piece']['source_path']} [{rep['piece']['variant']}] gate={rep['gate_verdict']} verdict={rep['verdict']} "
              f"brand={rep['brand_score']} (raw {rep['brand_score_uncapped']}) icp={rep['icp_relevance_score']} "
              f"blockers={blk} counts={rep['counts']}")
    else:
        print(js)
    return 1 if rep["gate_verdict"] == "block" else 0


if __name__ == "__main__":
    sys.exit(main())
