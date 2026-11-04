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

# Phase 0.2 readiness (2026-11-04)

Base verified as `9fc5e13ddc55397d4fd0136d50567aa7c8c3fdd8` on phase-0-1-runtime.
The supplied readiness patch applied cleanly; focused hardening was authorized by Itay.

- Installed requirements in an isolated Python environment (Pillow 12.3.0, fontTools 4.61.1).
- `scripts/test_all.sh --fresh`: 18/18 schema/migration/SQL steps; Guardian 19, file/import 8,
  font readiness 7, runtime 16. All 50 tests passed.
- Missing fontTools now blocks verification. Coverage includes Hebrew final forms, Latin, digits,
  typographic punctuation and the actual slide text. Unsupported glyphs block before drawing.
- Both renderers resolved DejaVuSans on this machine without the locked template fonts. Each rendered
  eight slides into temporary output, passed its existing QA, and all slides were visually inspected.
  No generated media or changed package hashes were committed; technical verification is not approval.
- test_013 separately verifies the agent boundary and the draft-state CHECK. Its assertions are outside
  their exception handlers. An isolated mutation test disables each protection in turn and confirms the
  smoke test fails; these schema mutations roll back and never touch the persistent DB.
- research.v0 is seeded draft/inactive by migration 013. All four prompts remain draft and inactive;
  all six site facts remain draft. No provider was connected and no real approval was granted.

# Phase 0.3 LLM wiring (2026-11-04)

- Based on phase-0-2-readiness at eaeea7647b7039fae51869c3658b8b4db13fa04b.
- Clean test_all.sh --fresh: 19/19 apply/SQL steps (schema through 014 and five rollback tests).
  Guardian 19, file/import 8, fonts 7, existing runtime 16 and new LLM suite 14: 64 passed.
- The LLM suite exercises an injected Chat Completions transport; no real provider is called.
  It reaches a packaged Hebrew text post using the existing Orchestrator with no fixture payloads,
  stops at insight/Core/piece approval and package preview, passes complete insight/Core/memory/fact
  context, shares the Core's budget and leaves unused site facts unapproved.
- Negative coverage: default-off and conflicting CLI modes, prompt/config blockers, input/budget
  limits before transport, concurrent budget reservations, timeout/unknown/HTTP/truncated/invalid JSON,
  missing usage, usage overruns, stable cache/resume, changed-context refusal, attempted model approvals,
  content rollback retaining costs and FactGate blocking unsupported claims even with no fact_ids.
- Persistent local DB check after testing: zero llm_calls, zero active prompts and zero approved facts.
  Human approvals in tests are synthetic and confined to isolated databases. No model/API key/provider
  prices were selected, payment flag enabled, publishing performed or hosted migration applied.
- Provider-specific compatibility and live semantic quality are not claimed by mocked tests. A human
  must select the endpoint/model/rates/budget/key, approve prompts/content and explicitly enable paid
  access before live validation. The accounting guard uses configured rates and conservative estimates,
  not a guarantee of provider-side billing. Editorial remains heuristic-stub-v0.
