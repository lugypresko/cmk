BEGIN;
SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='Codex'; SET LOCAL cmk.run_id='research-agents';
SET LOCAL search_path=cmk,public;
CREATE TABLE research_agent_tasks (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 work_item_id uuid NOT NULL REFERENCES work_items(id),
 research_run_id uuid NOT NULL REFERENCES research_runs(id),
 role text NOT NULL CHECK(role IN ('topics','hooks','synthesis')),
 prompt_version_id uuid NOT NULL REFERENCES prompt_versions(id),
 input_hash text NOT NULL,
 state text NOT NULL CHECK(state IN ('running','done','blocked')),
 output jsonb,
 error_code text,
 started_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 UNIQUE(work_item_id,role),
 CHECK(state<>'done' OR output IS NOT NULL)
);
CREATE TRIGGER research_agent_tasks_audit AFTER INSERT OR UPDATE ON research_agent_tasks
 FOR EACH ROW EXECUTE FUNCTION audit_status_change();
COMMIT;
