# guardian/ — SpecGate + FactGate + EditorialGuardian (v0)

Implements decision **D1**: the code gates (SpecGate, FactGate) are the only things that can **block**. EditorialGuardian only **scores** and can never override a Spec or Fact block. When a gate blocks, the brand score is capped at 74. Uses only the Python stdlib (3.10+).

```bash
python3 -m guardian runs/001-human-gates/linkedin_text_he.md                # variant B, prints JSON
python3 -m guardian piece.md --facts facts.json --variant A --twin twin.md --out report.json --summary
python3 -m guardian piece.json --claims claims.json --media-qa pass --strict
python3 -m unittest discover -s guardian/tests -t .                          # 19 tests
scripts/run_guardian_001.sh                                                  # run 001 → runs/001-human-gates/guardian_report_v2/
```
Exit codes: `0` gates pass · `1` gate block · `2` input/usage error.

## Inputs
- **Piece**: a run markdown file (YAML frontmatter, `text` body block, carousel `**n — headline**` slides, CoreAsset sections) or a ContentPiece JSON.
  - `--variant B` (default, the version Itay approved) drops paragraphs that contain `⟦STRIPE⟧` or `⟦NEED_APPROVED_FACT⟧`.
  - `--variant A` keeps those paragraphs and removes only the markers.
  - Every other `⟦…⟧` marker (e.g. `⟦ITAY_CONFIRM⟧`) stays in and blocks via S-02.
- **Rules** come from `guardian/fixtures/*.json`, exported from the local PGlite DB by `node scripts/export_fixtures.mjs`. This keeps D4 (Postgres is the source of truth), and `guardian_checklist.json` holds the check definitions.
- **Facts**: `--facts` (default `fixtures/approved_facts_db.json`). `fact_usable()` mirrors `usable_facts_v`: the fact must be approved, public, and not expired.
  - ⚠️ The current DB has **0 approved facts**. The only 6 rows are **draft** site facts (years, hours, offering structure, first read, method loop, confidentiality).
  - There is **no** Stripe or proof fact. Do not add numbers as "approved" until Itay approves them.
  - `fixtures/facts_TEST_ONLY.json` is synthetic and used by unit tests only.

## What each gate checks
| Gate | Checks (ids from guardian_checklist.json) |
|---|---|
| SpecGate | S-01 schema (approved ⇒ approved_by/at + scores; DB ids are info in file mode, major with `--strict`), S-02 unresolved `⟦…⟧`, S-03 format_spec, B-02 pricing/discount, B-07 guarantees, B-03/04/05 (regex part), B-06/L-01/L-02 language purity, B-09 agent approver, B-11 carousel 5–10, B-12 hashtags, F-T1..F-T7, F-C1..F-C7, CTA-01/02/03/05, L-05 twin parity, R-01 RenderQA |
| FactGate | extracts claims (numbers, third parties, credentials, results, generalisations), matches them to usable facts, flags stronger-than-fact numbers, fact_id not listed, and draft/expired facts (B-01, B-08, C-04/05/08). Accepts pre-extracted `--claims`. |
| EditorialGuardian | **`heuristic-stub-v0`**: brand rubric BR-1..9, ICP-1..6, penalties, and E-DUP (the same idea said twice). |

**Production:** EditorialGuardian will call an LLM with `brand_voice`, `icp_profile`, and the rubric, then return the same JSON shape. The stub is deliberately simple and **generous**: ICP lands at 95–100 on every run-001 piece, so it can't tell good pieces from mediocre ones yet. Don't treat its scores as calibrated. Calibrate it against the reference set before relying on the thresholds (brand 75 / ICP 70).

## Report (GuardianReport v2)
`{spec, fact, editorial, verdict}` plus these fields at the top level:
- `gate_verdict` (block|pass)
- `verdict` (pass|needs_changes|reject)
- `brand_score` (capped) and `brand_score_uncapped`
- `icp_relevance_score`, `findings`, `unsupported_claims`, `counts`, `checked_at`
- `piece.source_sha256`, so any later edit is visible (D2: audit only)

Verdict order:
1. A gate block → needs_changes (reject at revision ≥ 3).
2. Off-strategy scores → reject (as a recommendation only; a human sets `rejected`).
3. Any major finding → needs_changes. The exception is S-01 "approved without scores", which this report resolves.
4. Otherwise, the thresholds decide.

## Deviations and known gaps
- **R-01** blocks until DB RenderQA passes for the current revision/content/file hash. File-mode tests may use `--media-qa pass`. A run001 placeholder PDF was QA-tested; real carousel approval remains open.
- **B-02**: checklist v2 uses `\bNIS\b`, seeded in Postgres by 006 and exported with `export_fixtures.mjs`. The gate reads that exported DB checklist.
- **E-DUP** is a stub heuristic: two clauses with the same 5-word tail (questions skipped).
- **B-03/04/05/C-08** use regex/heuristics only. The LLM pass in production should cover tone and invented scenes.
- Hebrew number words ("עשרות", "מאות") are detected weakly. Prefer digits plus a fact_id.
- **F-T7** (link in body) and the duplicate-source check need DB context, so they are only partial in file mode.
