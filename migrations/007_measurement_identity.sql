BEGIN;
SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='Codex'; SET LOCAL cmk.run_id='phase-B';
-- Missing human success metrics are unknown, not zero.
ALTER TABLE cmk.performance_logs ALTER COLUMN icp_conversations DROP NOT NULL;
ALTER TABLE cmk.performance_logs ALTER COLUMN icp_conversations DROP DEFAULT;
CREATE UNIQUE INDEX performance_logs_import_identity ON cmk.performance_logs(content_id,window_label,source)
 WHERE content_id IS NOT NULL AND window_label IS NOT NULL;
ALTER TABLE cmk.past_content ADD COLUMN import_status text NOT NULL DEFAULT 'draft' CHECK(import_status IN ('draft','reviewed'));
COMMIT;
