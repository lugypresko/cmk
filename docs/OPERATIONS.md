# Local operations (human approval only)

Install: `npm install @electric-sql/pglite --prefix /tmp/pgl`.
Apply: `node scripts/apply_all.mjs --fresh`; export: `node scripts/export_fixtures.mjs`.
`--fresh` destroys local development data. Never use it on hosted data.

## Fact approval SQL for Itay to run after verifying the source

Replace the UUID and human name. These examples are documentation, never executed by agents.

```sql
BEGIN;
SET LOCAL cmk.actor_type='human';
SET LOCAL cmk.actor_name='Itay';
SET LOCAL cmk.run_id='human-fact-review';
UPDATE cmk.approved_facts SET status='approved', approved_by='Itay',
 approved_at=now(), last_verified_at=now() WHERE id='<fact-uuid>';
COMMIT;
```

## Piece approval SQL for Itay

Inspect the Guardian report, sources and rendered files first. Only pass verdicts go to approval.
Create a new revision for edits. D2 remains audit-only; approval is never revoked on edit.

```sql
BEGIN;
SET LOCAL cmk.actor_type='human';
SET LOCAL cmk.actor_name='Itay';
SET LOCAL cmk.run_id='human-piece-review';
UPDATE cmk.content_library SET status='approved', approved_by='Itay', approved_at=now()
 WHERE id='<piece-uuid>' AND status='in_review'
 AND guardian_report->>'verdict'='pass';
COMMIT;
```

For Core use `cmk.core_assets` with the same status/report guard. No agent executes these approvals.

## Production files and imports

Install Python dependencies from `requirements.txt`. Drop historical `.md` or `.json` files in
`imports/past_content/`. JSON accepts a row or array of `{body,language,url?,external_post_id?}`.
Markdown requires explicit language at import. Imported rows are drafts, with both exemplar flags false.

RenderQA accepts PDF files. Unsupported static formats fail closed and require a future extractor.
It verifies embedded fonts, pages, dimensions, per-page text and Hebrew RTL evidence. It does not
replace Itay's visual preview. Alt descriptions are required per page. PackageBuilder copies only
assets whose current hash equals their QA hash; caption text is preserved verbatim.

Measurement requires explicit content UUID, capture timestamp and window; the workbook's Post URL
must match that content's external URL. Only known aggregate metrics are imported, never viewer
identities. ICP conversations and time saved stay NULL unless explicit human manual values are supplied.
Re-import replaces that window's platform snapshot, preserving previously confirmed human metrics.

## Work items and prompts

`runtime/orchestrator.mjs` persists leases, state, step outputs and every transition in `work_events`.
`work_transitions` remains the allowed-transition policy. `run` resumes committed steps after a crash;
a live lease prevents duplicate workers. Exhausted work stops with a reason. Each derivative is independent.
Fixture mode is explicit through `context.core`/`context.piece`; it uses supplied text only, without an LLM.
Production judgment providers require an active approved DB prompt. No API keys or LLM calls are built in.

Draft prompts are seeded by 008. Itay reviews the body, then can approve/activate a specific UUID:

```sql
BEGIN;
SET LOCAL cmk.actor_type='human'; SET LOCAL cmk.actor_name='Itay';
SET LOCAL cmk.run_id='human-prompt-review';
UPDATE cmk.prompt_versions SET status='approved',approved_by='Itay',approved_at=now(),is_active=true
 WHERE id='<prompt-uuid>' AND status='draft';
COMMIT;
```

Research inserts draft insights. Core/Repurposer validate JSON against contracts.md before draft insertion.
Core and insight approval are separate human gates. `resumeHuman` only resumes after checking the DB;
it never approves the subject itself. ErrorWatcher records classification, proposal, reason, scope and a
baseline Guardian replay. The replay is explicitly a stub, never evidence that a proposed rule was tested.

## CLI examples

```bash
node scripts/cmk.mjs enqueue --kind core --input fixture-workflow.json
node scripts/cmk.mjs run --id WORK_UUID
node scripts/cmk.mjs status
node scripts/cmk.mjs resume --id WORK_UUID --confirmer Itay
node scripts/cmk.mjs qa --id CONTENT_UUID --file carousel.pdf --alt alt-text.json
node scripts/cmk.mjs package --id CONTENT_UUID
node scripts/cmk.mjs import-past --file imports/past_content/post.md --language he
node scripts/cmk.mjs measure --id CONTENT_UUID --file analytics.xlsx --window 72h --captured-at 2026-11-03T12:00:00+02:00
node scripts/cmk.mjs propose-slots --start 2026-11-04
node scripts/cmk.mjs confirm-slot --id SLOT_UUID --confirmer Itay
node scripts/cmk.mjs begin-manual --id CONTENT_UUID --account itay-profile --slot SLOT_UUID
node scripts/cmk.mjs outcome --attempt ATTEMPT_UUID --outcome unknown
node scripts/cmk.mjs posted-url --id INSTANCE_UUID --url https://www.linkedin.com/posts/POST --confirmer Itay
```

The CLI never approves content/facts/Core. `--confirmer` is a local operator declaration, not authentication.
Run it only in a trusted environment; production still needs authenticated DB roles. A `posted-url` command
records Itay's explicit report that the post is live. It performs no network publication or verification.
Unknown outcomes require Itay to check LinkedIn and record the URL or resolve the instance explicitly in SQL.
There is no automatic retry. A known failed attempt can be started again only by an explicit `begin-manual`.

The v0 Scheduler creates a draft plan; slot enum has no `draft`, so unconfirmed proposals use `filled`.
It leaves missing candidates `open`. Daily cap is always 1 LinkedIn post, across plans, in Asia/Jerusalem.
No Calendar integration is created. Disabled formats are not selected. Quiet days stay the manual
`quiet_days` list; Hebrew holidays are not added for you.

## Mark a piece exact-repeatable

Do this only after you have approved that revision and checked the package. The statement stores the
current content hash and the pass-QA asset checksums. Set both an end date and a repeat count. The
scheduler can then propose the same `content_id` and revision every 14 days until either limit.
It will refuse a later slot if the text or assets change, or if a referenced fact expires or is retired.
Your approval stays in place either way (D2). A piece you do not mark, or one whose facts changed,
still needs a new revision, Guardian, and a new approval. LinkedIn `text_post` and `carousel` only.
Confirm the slot the same way as any other slot, then record the live URL with `begin-manual` /
`posted-url`. Each repeat is its own publish record. Nothing is auto-posted.

```sql
BEGIN;
SET LOCAL cmk.actor_type='human';
SET LOCAL cmk.actor_name='Itay';
SET LOCAL cmk.run_id='human-exact-repeat';
UPDATE cmk.content_library SET
  is_exact_repeatable = true,
  repeat_every_days = 14,
  repeat_until = DATE '2027-06-01',
  max_repeats = 4,
  repeat_approved_content_hash = content_hash(content_library),
  repeat_asset_hashes = coalesce((
    SELECT jsonb_agg(sha256 ORDER BY sha256)
    FROM cmk.media_assets
    WHERE content_id = content_library.id
      AND content_revision = content_library.revision
      AND qa_status = 'pass'), '[]'::jsonb)
WHERE id = '<piece-uuid>'
  AND status = 'approved'
  AND NOT edited_after_approval
  AND channel = 'linkedin'
  AND format IN ('text_post','carousel')
  AND approved_content_hash = content_hash(content_library);
COMMIT;
```

Run `scripts/test_all.sh --fresh` for a clean local validation, or omit `--fresh` to retain local data.
The journal sync restores Markdown entries after a reset without modifying old entries. Historical
noncanonical journal IDs are mapped to their canonical filename IDs in the DB mirror only.

A manual metric example adds `--manual --icp_conversations 1 --confirmer Itay` to the measurement command.
No baseline or ICP count is inferred from engagement. Time saved has the same explicit manual requirement.

Read-only inspection: `node scripts/q.mjs "SELECT * FROM cmk.work_events ORDER BY id DESC LIMIT 20"`.
`q.mjs` runs a read-only transaction. Use a deliberate operator SQL transaction for human approvals.
