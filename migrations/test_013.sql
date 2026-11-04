-- Rolled-back smoke test: separate agent authorization and draft-state checks.
SET search_path = cmk, public;
DO $$
DECLARE r prompt_versions; blocked boolean; constraint_name text;
BEGIN
  SELECT * INTO r FROM prompt_versions WHERE prompt_key='research.v0' AND version=1;
  IF NOT FOUND THEN RAISE EXCEPTION 'research.v0 missing'; END IF;
  IF r.status <> 'draft' OR r.is_active OR r.approved_by IS NOT NULL OR r.approved_at IS NOT NULL THEN
    RAISE EXCEPTION 'research.v0 must stay a non-active draft pending human review';
  END IF;

  PERFORM set_config('cmk.actor_type','agent',true);
  PERFORM set_config('cmk.actor_name','readiness-test',true);
  PERFORM set_config('cmk.run_id','test-013-agent',true);
  blocked := false;
  BEGIN
    UPDATE prompt_versions SET is_active=true WHERE id=r.id;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'human approval/operational status required for prompt_versions' THEN RAISE; END IF;
    blocked := true;
  END;
  -- Assertion is outside the handler: it cannot catch its own failure.
  IF NOT blocked THEN RAISE EXCEPTION 'agent activation was not blocked by the human boundary'; END IF;

  PERFORM set_config('cmk.actor_type','human',true);
  PERFORM set_config('cmk.actor_name','TEST HUMAN',true);
  PERFORM set_config('cmk.run_id','test-013-draft-check',true);
  blocked := false;
  BEGIN
    UPDATE prompt_versions SET is_active=true WHERE id=r.id;
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS constraint_name = CONSTRAINT_NAME;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='cmk.prompt_versions'::regclass
                   AND conname=constraint_name AND pg_get_constraintdef(oid) LIKE '%is_active%') THEN RAISE; END IF;
    blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'human activation of a draft was not blocked by CHECK'; END IF;

  SELECT * INTO r FROM prompt_versions WHERE id=r.id;
  IF r.is_active OR r.status<>'draft' OR r.approved_by IS NOT NULL OR r.approved_at IS NOT NULL THEN
    RAISE EXCEPTION 'prompt changed during negative tests';
  END IF;
  RAISE NOTICE 'test_013 passed: agent boundary and draft CHECK both block';
END $$;
