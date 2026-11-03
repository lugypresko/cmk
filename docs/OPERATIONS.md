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
