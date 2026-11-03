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
