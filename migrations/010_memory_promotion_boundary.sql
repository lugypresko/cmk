BEGIN;
SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='Codex'; SET LOCAL cmk.run_id='phase-D';
SET LOCAL search_path=cmk,public;
CREATE FUNCTION correction_promotion_boundary() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF coalesce(nullif(current_setting('cmk.actor_type',true),''),'agent')<>'human' THEN
  IF TG_OP='INSERT' THEN
   IF NEW.promoted_to IS NOT NULL OR NEW.promoted_at IS NOT NULL THEN RAISE EXCEPTION 'Memory promotion is human-only'; END IF;
  ELSIF NEW.promoted_to IS DISTINCT FROM OLD.promoted_to OR NEW.promoted_at IS DISTINCT FROM OLD.promoted_at
      OR NEW.promoted_ref_id IS DISTINCT FROM OLD.promoted_ref_id THEN RAISE EXCEPTION 'Memory promotion is human-only';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER correction_human_promotion BEFORE INSERT OR UPDATE ON correction_log FOR EACH ROW EXECUTE FUNCTION correction_promotion_boundary();
CREATE FUNCTION past_content_human_flags() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF coalesce(nullif(current_setting('cmk.actor_type',true),''),'agent')<>'human' THEN
  IF TG_OP='INSERT' THEN
   IF NEW.is_exemplar OR NEW.is_anti_example THEN RAISE EXCEPTION 'Exemplar flags are human-only'; END IF;
  ELSIF NEW.is_exemplar IS DISTINCT FROM OLD.is_exemplar OR NEW.is_anti_example IS DISTINCT FROM OLD.is_anti_example THEN
   RAISE EXCEPTION 'Exemplar flags are human-only';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER past_content_human_flags BEFORE INSERT OR UPDATE ON past_content FOR EACH ROW EXECUTE FUNCTION past_content_human_flags();
COMMIT;
