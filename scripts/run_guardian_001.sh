#!/usr/bin/env bash
# Run SpecGate + FactGate + EditorialGuardian(stub) on run 001 pieces, both variants.
# Facts = guardian/fixtures/approved_facts_db.json (export of local PGlite; all rows are DRAFT).
set -u
cd "$(dirname "$0")/.."
RUN=runs/001-human-gates; OUT=$RUN/guardian_report_v2; mkdir -p "$OUT"
node scripts/export_fixtures.mjs >/dev/null
for base in linkedin_text carousel core_asset; do
  for lang in he en; do
    twin=$([ $lang = he ] && echo en || echo he)
    for v in B A; do
      python3 -m guardian "$RUN/${base}_${lang}.md" --variant $v --twin "$RUN/${base}_${twin}.md" \
        --out "$OUT/${base}_${lang}.$v.json" --summary
    done
  done
done
python3 - "$OUT" <<'PY'
import json, sys, pathlib, datetime
out = pathlib.Path(sys.argv[1]); rows = []
for p in sorted(out.glob("*.[AB].json")):
    r = json.loads(p.read_text())
    rows.append({"file": p.name, "piece": r["piece"]["source_path"], "variant": r["piece"]["variant"],
                 "status_in_file": r["piece"].get("status_in_file"), "gate_verdict": r["gate_verdict"], "verdict": r["verdict"],
                 "brand_score": r["brand_score"], "brand_score_uncapped": r["brand_score_uncapped"],
                 "icp_relevance_score": r["icp_relevance_score"],
                 "blockers": sorted({f["check_id"] for f in r["findings"] if f["severity"] == "blocker"}),
                 "majors": sorted({f["check_id"] for f in r["findings"] if f["severity"] == "major"})})
json.dump({"run": "001-human-gates", "generated_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
           "facts_source": "guardian/fixtures/approved_facts_db.json (local PGlite export; 0 approved facts, 6 draft site facts)",
           "editorial_scorer": "heuristic-stub-v0 (not the production LLM scorer)", "pieces": rows},
          open(out / "summary.json", "w"), ensure_ascii=False, indent=2)
PY
