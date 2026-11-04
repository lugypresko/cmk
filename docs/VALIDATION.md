# Phase 0–1 validation (2026-11-03)

Validated locally on PGlite PostgreSQL; no hosted/prod database changed.

- Fresh apply: schema + 002–012 + four rollback SQL smoke tests, 16/16 steps passed.
- Guardian unit suite: 19 passed.
- File/import unit suite: 8 passed, including embedded PDF fonts, text drift, alt text, page count,
  correct Hebrew RTL and incorrectly ordered Hebrew, package approval/edit guards and asset tamper.
- Runtime integration suite: 15 passed in a separate in-memory DB. Covers persisted Workflow A→B human
  gates for HE/EN text/carousel, per-derivative failure isolation, lease exclusion/recovery, exhaustion,
  contract rejection, human approval boundaries, package→schedule→manual-record flow, unknown refusal
  at API and DB, measurement idempotence/NULL success metrics, read-only baseline replay, and the exact
  14-day repeat: same content id and hash on the next cycle, including across an open plan and inside
  the 4-day same-core gap, then blocked on asset checksum drift, an expired fact, a retired fact, and
  an edit after approval. That edit left the approval in place.
- Run001 EN carousel Variant B: temporary placeholder PDF, eight pages. RenderQA passed open/count/
  text/dimensions/embedded fonts/alt checks; first page rendered and visually inspected. This is technical
  QA only, not content approval or a final carousel production design. No placeholder file is committed.
- `scripts/run_guardian_001.sh` executed. Actual carousels remain blocked by R-01 without approved rendered
  assets; Variant A also blocks unapproved facts. Actual Core files retain S-02 human-confirmation markers.
  Historical report snapshots were preserved. No business approval was granted.
- Local demo: `scripts/dry_run.mjs` created a fixture work item and stopped at `human_gate:approve_insight`.
  `work_events` shows its persisted transitions. No publication instance was created by the demo.
- Data check: all six site facts remain draft. All three prompt proposals remain draft and inactive.

## Open human work

- Verify and approve site/proof facts and Hebrew seeds as appropriate.
- Resolve real Core placeholders, review Core and carousel, and approve exact revisions.
- Import 20–50 real posts, mark exemplars and calibrate editorial on 20+ examples.
- Review/activate prompts; supply a production judgment provider and Research prompt before live generation.
- Set time-saved baseline and confirm ICP conversation metrics.
- Preview final media and confirm individual schedule slots before manual publishing.
- To mark a piece exact-repeatable, use the SQL in docs/OPERATIONS.md. Set both the end date and the
  repeat count. The scheduler will not invent that grant.

## Deliberate limits

EditorialGuardian is heuristic-stub-v0, and ErrorWatcher replay tests the baseline only. No candidate
rule is automatically promoted. RenderQA currently supports extractable PDFs; other static formats fail
closed. Local `--confirmer` is an operator declaration, not authentication. Authenticated service roles,
hosted migration rollout, real media production/storage and a production LLM integration remain future
operational work. No new format, higher threshold, automatic publisher or volume ramp was enabled.
Exact repeat is opt-in per piece (docs/OPERATIONS.md). It does not publish by itself.

Run 001 local E2E slice (2026-11-04): `scripts/run_001_e2e_demo.sh` and `python -m cmk_ops` read and write `runs/001-human-gates/out/`. The checked-in HE Variant B package is `ready_for_human_approval`, not an approval and not a publish. Migration `012_e2e_chain_slice.sql` is the renumbered grill migration. Brief, Ingest, Research, and LeadOps remain the stub journal.
