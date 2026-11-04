-- Smoke test for 011 (throwaway). Run after schema + 002..011.
-- Proves the rule shape, the human-only grant, and that D2 still allows an edit
-- after the piece is marked exact-repeatable (approval is not revoked).
SET search_path = cmk, public;
DO $$
DECLARE bv uuid; icp uuid; ca uuid; fs uuid; cid uuid; r content_library;
BEGIN
  SELECT id INTO bv FROM brand_voice WHERE is_active;
  SELECT id INTO icp FROM icp_profiles LIMIT 1;
  INSERT INTO core_assets (brand_voice_id, icp_profile_id, title, body_en)
    VALUES (bv, icp, 'exact repeat smoke', 'synthetic') RETURNING id INTO ca;
  SELECT id INTO fs FROM format_specs
    WHERE format='text_post' AND channel='linkedin' AND language='en' AND is_active;
  INSERT INTO content_library (core_asset_id, format_spec_id, format, channel, language, body)
    VALUES (ca, fs, 'text_post', 'linkedin', 'en', 'exact repeat body') RETURNING id INTO cid;

  PERFORM set_config('cmk.actor_type','human',true);
  PERFORM set_config('cmk.actor_name','Itay',true);
  UPDATE content_library
    SET status='approved', brand_score=80, icp_relevance_score=75, approved_by='Itay', approved_at=now()
    WHERE id=cid;
  SELECT * INTO r FROM content_library WHERE id=cid;

  PERFORM set_config('cmk.actor_type','agent',true);
  BEGIN
    UPDATE content_library
      SET is_exact_repeatable=true, repeat_every_days=14, repeat_until=DATE '2027-06-01', max_repeats=3,
          repeat_approved_content_hash=content_hash(r), repeat_asset_hashes='[]'::jsonb
      WHERE id=cid;
    RAISE EXCEPTION 'agent gate did not fire';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'agent gate%' THEN RAISE; END IF;
    RAISE NOTICE 'agent exact-repeat grant blocked';
  END;
  IF (SELECT is_exact_repeatable FROM content_library WHERE id=cid) THEN
    RAISE EXCEPTION 'agent grant persisted';
  END IF;

  PERFORM set_config('cmk.actor_type','human',true);
  UPDATE content_library
    SET is_exact_repeatable=true, repeat_every_days=14, repeat_until=DATE '2027-06-01', max_repeats=3,
        repeat_approved_content_hash=content_hash(r), repeat_asset_hashes='[]'::jsonb
    WHERE id=cid;
  SELECT * INTO r FROM content_library WHERE id=cid;
  IF NOT r.is_exact_repeatable OR r.repeat_every_days <> 14 OR r.max_repeats <> 3
     OR r.repeat_until <> DATE '2027-06-01' OR r.repeats_done <> 0
     OR r.repeat_approved_content_hash <> content_hash(r) THEN
    RAISE EXCEPTION 'exact repeat rule was not stored';
  END IF;

  BEGIN
    UPDATE content_library SET max_repeats=NULL WHERE id=cid;
    RAISE EXCEPTION 'shape check did not fire';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'exact repeat shape ok';
  END;

  BEGIN
    UPDATE content_library SET repeat_every_days=4 WHERE id=cid;
    RAISE EXCEPTION 'cadence check did not fire';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'cadence floor ok';
  END;

  BEGIN
    UPDATE content_library SET repeat_asset_hashes='["nope"]'::jsonb WHERE id=cid;
    RAISE EXCEPTION 'asset hash check did not fire';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'asset hash shape ok';
  END;

  -- D2: an edit after the grant is still allowed. Approval stays. The flag stays.
  -- The scheduler, not a freeze trigger, refuses the repeat once the hash drifts.
  PERFORM set_config('cmk.actor_type','agent',true);
  UPDATE content_library SET body='exact repeat body edited' WHERE id=cid;
  SELECT * INTO r FROM content_library WHERE id=cid;
  IF r.status <> 'approved' OR r.approved_by IS NULL OR NOT r.edited_after_approval
     OR NOT r.is_exact_repeatable OR r.repeat_approved_content_hash IS NULL THEN
    RAISE EXCEPTION 'D2 edit was blocked or approval was revoked';
  END IF;
  IF r.repeat_approved_content_hash = content_hash(r) THEN
    RAISE EXCEPTION 'approved repeat hash should stay on the pre-edit version';
  END IF;

  RAISE NOTICE 'test_011 passed';
END $$;
