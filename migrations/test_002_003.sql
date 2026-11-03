SET search_path = cmk, public;
-- approve a fact-free core + piece path; ensure new-format guard works
DO $$
DECLARE bv uuid; icp uuid; ca uuid; fs uuid; fs2 uuid; cid uuid; ok boolean;
BEGIN
  SELECT id INTO bv FROM brand_voice WHERE is_active; SELECT id INTO icp FROM icp_profiles LIMIT 1;
  INSERT INTO core_assets (brand_voice_id, icp_profile_id, title, body_en) VALUES (bv, icp, 't', 'b') RETURNING id INTO ca;
  SELECT id INTO fs FROM format_specs WHERE format='text_post' AND channel='linkedin' AND language='en' AND is_active;
  INSERT INTO content_library (core_asset_id, format_spec_id, format, channel, language, body) VALUES (ca, fs, 'text_post','linkedin','en','x') RETURNING id INTO cid;
  PERFORM set_config('cmk.actor_type','human',true); PERFORM set_config('cmk.actor_name','Itay',true);
  UPDATE content_library SET status='approved', brand_score=80, icp_relevance_score=75, approved_by='Itay', approved_at=now() WHERE id=cid;
  -- new format without payload must fail
  SELECT id INTO fs2 FROM format_specs WHERE format='poll' AND language='en';
  BEGIN
    INSERT INTO content_library (core_asset_id, format_spec_id, format, channel, language, body) VALUES (ca, fs2, 'poll','linkedin','en','x');
    RAISE EXCEPTION 'payload check did not fire';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'payload check ok'; END;
  INSERT INTO content_library (core_asset_id, format_spec_id, format, channel, language, body, payload)
    VALUES (ca, fs2, 'poll','linkedin','en','x', '{"question":"q","options":["a","b"],"duration_days":7}') RETURNING id INTO cid;
  BEGIN
    UPDATE content_library SET status='approved', brand_score=80, icp_relevance_score=75, approved_by='Itay', approved_at=now() WHERE id=cid;
    RAISE EXCEPTION 'format gate did not fire';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'format gate%' THEN RAISE; END IF; RAISE NOTICE 'format gate ok: %', SQLERRM; END;
  BEGIN UPDATE format_specs SET is_active=true WHERE id=fs2; RAISE EXCEPTION 'stub gate did not fire';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'stub gate ok'; END;
  BEGIN UPDATE audit_log SET note='x'; RAISE EXCEPTION 'x'; EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'audit_log is append-only' THEN RAISE; END IF; END;
END $$;
