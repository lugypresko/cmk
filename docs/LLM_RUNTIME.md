# First LLM-generated artifact (local, human-gated)

This path extends the existing runtime; it does not replace the Orchestrator or prompt keys.
The provider adapter uses the non-streaming OpenAI-compatible Chat Completions protocol.
No provider, model, API key, pricing or paid permission is selected by this repository.
No real model call was used to validate this implementation.

## Prepare

Use Node 20+ and the Python dependencies in requirements.txt. No new Node package is needed for transport.

Apply migrations through 014 with `scripts/test_all.sh --fresh` on local development data only.
`--fresh` deletes local data. Otherwise run `node scripts/apply_all.mjs` to preserve it.
The new tests use separate in-memory databases and synthetic human approvals only.

Itay reviews and activates **existing** `research.v0`, `core_creator.v0` and `repurposer.v0`
prompts using the human SQL path in OPERATIONS.md. They remain draft/inactive until then.
`editorial_guardian.v0` need not be activated to retain the explicitly labelled heuristic scorer.
The first live path here targets a Hebrew LinkedIn text post; final quality review is human.

Supply configuration in the local process environment, never in a tracked file or work-item JSON:

```bash
export CMK_LLM_API_BASE_URL='https://YOUR_PROVIDER/v1'
export CMK_LLM_MODEL='YOUR_CHAT_COMPLETIONS_MODEL'
export CMK_LLM_API_KEY='YOUR_LOCAL_SECRET'
export CMK_LLM_INPUT_USD_PER_MILLION='VERIFIED_NUMERIC_INPUT_PRICE'
export CMK_LLM_OUTPUT_USD_PER_MILLION='VERIFIED_NUMERIC_OUTPUT_PRICE'
export CMK_LLM_RUN_BUDGET_USD='YOUR_NUMERIC_USD_LIMIT'
export CMK_LLM_MAX_OUTPUT_TOKENS='2048'
export CMK_LLM_MAX_INPUT_BYTES='65536'
export CMK_LLM_TIMEOUT_MS='30000'
```

Both `CMK_LLM_PAID_CALLS_ENABLED=true` and the CLI flag `--allow-paid` are required before
any transport call. A key alone never enables calls. Missing/invalid configuration blocks.
The default `run` performs a preflight only; it does not manufacture a generated draft.

## Execute in stages

```bash
node scripts/cmk.mjs start --idea 'Describe one leadership bottleneck to examine' --language he
node scripts/cmk.mjs run --id CORE_WORK_UUID
# Default above: dry-run, zero external calls, exposes the next prompt/human blocker.

# Only after Itay explicitly enables paid calls locally:
CMK_LLM_PAID_CALLS_ENABLED=true node scripts/cmk.mjs run --id CORE_WORK_UUID --allow-paid
```

The first response is a draft insight. Review it and approve only its actual UUID in a human SQL
transaction, then `resume --id CORE_WORK_UUID --confirmer Itay`. This command only checks/resumes;
it grants no approval. Run again with explicit paid flags to create the Core, then stop for its
Guardian report and human approval. After approval, `resume` and `run --offline` finish the Core item.

```bash
node scripts/cmk.mjs multiply --id CORE_WORK_UUID --language he
# Returns an independent derivative work UUID, sharing the Core's durable generation budget.
CMK_LLM_PAID_CALLS_ENABLED=true node scripts/cmk.mjs run --id POST_WORK_UUID --allow-paid
# Stops at Guardian findings or human piece approval.
# After Itay separately approves the specific piece UUID:
node scripts/cmk.mjs resume --id POST_WORK_UUID --confirmer Itay
node scripts/cmk.mjs run --id POST_WORK_UUID --offline
```

`--offline` can execute deterministic stages or supplied fixtures, but never calls a model.
The final command writes `packages/<content UUID>/r<revision>/package.json` and post.txt, then
stops at `human_gate:package_preview`. The work context contains `package_path` for retrieval.
Stop here for the first artifact; scheduling, hosted DB and publishing are unnecessary.
The CLI's `--confirmer` is a trusted local operator declaration, not an authentication system.
`--fixture` preserves the previous explicit test path. Paid CLI mode refuses fixture payloads.

## Context and facts

Research receives the idea/source notes; Core creation receives the full approved insight;
Repurposer receives the full approved Core and the matching active format spec. Every model
request includes active brand/ICP memory, the approved public unexpired facts allowed for public
posts, the approved prompt version and a draft output contract. Private insights are refused.
Do not supply private or unconsented source notes: initial idea/source notes are explicit model input.

No global approval of six site facts is required. Unreferenced drafts stay irrelevant. A returned
fact UUID must be usable or the step stops at `human_gate:approve_used_fact:<UUID>`. Other factual
claims are still scanned by FactGate, even without fact_ids; unsupported claims block review.
The operator can approve the actually needed fact in a separate human transaction or request a
new draft without that claim. `pending_fact_keys` by itself is informational, not an approval mandate.

All generated rows remain draft until deterministic gates move them into review; only a human can
approve. The uncalibrated editorial score never overrides a code gate. Review wording and sources.
Calibration on 20+ exemplars remains necessary before trusting scores to reduce human review or
raising thresholds/volume; it is not required to obtain the first human-reviewed artifact.

## Budget, audit and crash recovery

Migration 014 adds `llm_runs` and `llm_calls`. Core and derivatives share a durable run ID.
Before a network call, a committed reservation is charged against that run's fixed budget.
Reservations use UTF-8 input bytes plus a protocol margin and maximum completion tokens, priced
at the operator's configured rates. Actual reported token usage replaces the estimate when present.
These are local accounting guards, not provider billing guarantees. Verify model-specific rates,
Chat Completions parameter support and provider-side spending controls before enabling payment.
If usage exceeds the reservation/output limit, output is blocked and the reported cost is retained.

External requests run outside the content-write transaction: invalid output or a later rollback
cannot erase a paid call. Successful JSON responses are cached under work-item ID + step + request
hash and reused on crash-resume. Changed context, reserved/unknown or failed calls never auto-resend.
A lease prevents a concurrent worker from processing the same step. A crash before/after send may
leave `reserved`; resolve that ambiguity manually rather than assuming no charge.
HTTP errors, invalid/truncated JSON and unknown transport outcomes retain the reservation.
No built-in retry loop or live automatic retry is present.

After fixing a missing approval/configuration issue, use `retry --id UUID --confirmer Itay` to
resume a blocked generation step. This never bypasses approval or the call ledger. Failed/unknown
calls require operator investigation or an explicit new work item/revision; they are not resent by retry.

`llm-status --id WORK_UUID` and `SELECT ... FROM cmk.llm_calls` show spend/state.
Each reservation/outcome writes an audit_log row with prompt ID, model, run, state, token usage and
cost. Neither keys, raw request/response bodies nor provider error text are copied to audit_log.
Draft outputs are retained in the call ledger for recovery and are not publication approvals.

Protocol reference: https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create
Model/provider compatibility must be checked for max_completion_tokens and JSON object mode.

Insight approval uses the same explicit actor convention as Core/piece approvals. This example
is for the human operator after reviewing the generated insight; the runner never executes it:

```sql
BEGIN;
SET LOCAL cmk.actor_type='human'; SET LOCAL cmk.actor_name='Itay';
SET LOCAL cmk.run_id='human-insight-review';
UPDATE cmk.core_insights SET status='approved',approved_by='Itay',approved_at=now()
 WHERE id='<reviewed-insight-uuid>' AND status='draft';
COMMIT;
```
