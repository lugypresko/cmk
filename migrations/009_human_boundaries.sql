BEGIN;
SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='Codex'; SET LOCAL cmk.run_id='phase-D';
SET LOCAL search_path=cmk,public;
-- Preserve D2: edits stay audit-only. Only granting/changing approval is human-only.
CREATE FUNCTION human_approval_boundary() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n jsonb:=to_jsonb(NEW); o jsonb:=CASE WHEN TG_OP='UPDATE' THEN to_jsonb(OLD) ELSE '{}'::jsonb END;
BEGIN
 IF coalesce(nullif(current_setting('cmk.actor_type',true),''),'agent') <> 'human' THEN
  IF (n->>'approved_by' IS DISTINCT FROM o->>'approved_by') OR (n->>'approved_at' IS DISTINCT FROM o->>'approved_at')
   OR (n->>'status' IN ('approved','scheduled','published','rejected','archived') AND n->>'status' IS DISTINCT FROM o->>'status')
   OR (TG_TABLE_NAME='prompt_versions' AND n->>'is_active'='true' AND n->>'is_active' IS DISTINCT FROM o->>'is_active') THEN
   RAISE EXCEPTION 'human approval/operational status required for %',TG_TABLE_NAME;
  END IF;
 END IF;
 IF TG_TABLE_NAME IN ('content_library','core_assets') AND n->>'status' IN ('approved','scheduled','published')
    AND n->'guardian_report'->>'gate_verdict'='block' THEN
  RAISE EXCEPTION 'code gate block cannot be overridden';
 END IF;
 RETURN NEW;
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['approved_facts','core_insights','core_assets','content_library','prompt_versions'] LOOP
 EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION human_approval_boundary()',t||'_human_boundary',t);
 END LOOP;
END $$;
-- Agent-created lead suggestions cannot choose a non-default human owner.
CREATE FUNCTION lead_owner_insert_boundary() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF coalesce(current_setting('cmk.actor_type',true),'agent')<>'human' AND NEW.owner<>'Itay' THEN
 RAISE EXCEPTION 'lead owner is human-only'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER lead_owner_insert BEFORE INSERT ON lead_threads FOR EACH ROW EXECUTE FUNCTION lead_owner_insert_boundary();
COMMIT;
