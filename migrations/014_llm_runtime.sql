BEGIN;
SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='Codex'; SET LOCAL cmk.run_id='phase-0-3';
SET LOCAL search_path=cmk,public;
-- Local spend accounting uses operator-supplied rates; no provider prices are assumed.
CREATE TABLE llm_runs (
 id text PRIMARY KEY,
 budget_microusd bigint NOT NULL CHECK(budget_microusd>0),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE llm_calls (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 run_id text NOT NULL REFERENCES llm_runs(id),
 call_key text NOT NULL UNIQUE,
 request_hash text NOT NULL,
 prompt_version_id uuid NOT NULL REFERENCES prompt_versions(id),
 provider_origin text NOT NULL,
 model text NOT NULL,
 state text NOT NULL CHECK(state IN ('reserved','succeeded','failed','unknown')),
 reserved_microusd bigint NOT NULL CHECK(reserved_microusd>0),
 charged_microusd bigint NOT NULL CHECK(charged_microusd>=0),
 input_rate numeric NOT NULL CHECK(input_rate>=0),
 output_rate numeric NOT NULL CHECK(output_rate>=0),
 input_tokens integer,
 output_tokens integer,
 output jsonb,
 error_code text,
 created_at timestamptz NOT NULL DEFAULT now(),
 finished_at timestamptz,
 CHECK(state<>'succeeded' OR output IS NOT NULL)
);
CREATE FUNCTION audit_llm_call() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO audit_log(actor_type,actor_name,action,table_name,row_id,prompt_version_id,run_id,note,changes)
 VALUES(current_setting('cmk.actor_type')::actor_type,current_setting('cmk.actor_name'),'other','llm_calls',NEW.id,
 NEW.prompt_version_id,NEW.run_id,'llm_'||NEW.state,
 jsonb_build_object('model',NEW.model,'state',NEW.state,'reserved_microusd',NEW.reserved_microusd,
 'charged_microusd',NEW.charged_microusd,'input_tokens',NEW.input_tokens,'output_tokens',NEW.output_tokens,'error_code',NEW.error_code));
 RETURN NEW;
END $$;
CREATE TRIGGER llm_call_audit AFTER INSERT OR UPDATE ON llm_calls FOR EACH ROW EXECUTE FUNCTION audit_llm_call();
-- Successful model responses are reusable on crash-resume; never silently overwrite them.
CREATE FUNCTION llm_call_terminal() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.state<>'reserved' THEN RAISE EXCEPTION 'LLM call outcome is terminal; no automatic resend'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER llm_call_terminal BEFORE UPDATE ON llm_calls FOR EACH ROW EXECUTE FUNCTION llm_call_terminal();
COMMIT;
