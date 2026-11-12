BEGIN;
SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='Codex'; SET LOCAL cmk.run_id='focused-research';
SET LOCAL search_path=cmk,public;
CREATE TABLE research_runs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 profile_id uuid NOT NULL REFERENCES research_profiles(id),
 profile_hash text NOT NULL,
 provider text NOT NULL CHECK(provider IN ('brave','import')),
 state text NOT NULL CHECK(state IN ('collecting','ready','partial','failed')),
 budget_microusd bigint NOT NULL DEFAULT 0 CHECK(budget_microusd>=0),
 request_cost_microusd bigint NOT NULL DEFAULT 0 CHECK(request_cost_microusd>=0),
 max_requests integer NOT NULL CHECK(max_requests BETWEEN 1 AND 100),
 evidence jsonb NOT NULL DEFAULT '[]',
 coverage jsonb NOT NULL DEFAULT '[]',
 query_plan jsonb NOT NULL DEFAULT '[]',
 rejected jsonb NOT NULL DEFAULT '[]',
 created_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz
);
CREATE TABLE research_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 research_run_id uuid NOT NULL REFERENCES research_runs(id),
 request_key text NOT NULL,
 query text NOT NULL,
 state text NOT NULL CHECK(state IN ('reserved','succeeded','failed','unknown')),
 charged_microusd bigint NOT NULL CHECK(charged_microusd>0),
 error_code text,
 created_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 UNIQUE(research_run_id,request_key)
);
CREATE FUNCTION audit_research_request() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO audit_log(actor_type,actor_name,action,table_name,row_id,run_id,note,changes)
 VALUES(current_setting('cmk.actor_type')::actor_type,current_setting('cmk.actor_name'),'other','research_requests',NEW.id,
 NEW.research_run_id::text,'research_source_'||NEW.state,jsonb_build_object('state',NEW.state,'charged_microusd',NEW.charged_microusd,'error_code',NEW.error_code));
 RETURN NEW;
END $$;
CREATE TRIGGER research_request_audit AFTER INSERT OR UPDATE ON research_requests FOR EACH ROW EXECUTE FUNCTION audit_research_request();
CREATE FUNCTION research_request_terminal() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.state<>'reserved' THEN RAISE EXCEPTION 'Research request is terminal; no automatic resend'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER research_request_terminal BEFORE UPDATE ON research_requests FOR EACH ROW EXECUTE FUNCTION research_request_terminal();
ALTER TABLE core_insights ADD COLUMN research_run_id uuid REFERENCES research_runs(id), ADD COLUMN research_report jsonb;
COMMIT;
