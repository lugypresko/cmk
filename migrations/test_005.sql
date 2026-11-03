-- Smoke test for 005 (throwaway DB only). Run after schema + 002 + 003 + 004 + 005.
SET search_path = cmk, public;
DO $$
DECLARE bv uuid; icp uuid; ca uuid; fs uuid; cid uuid; pi uuid; w uuid; lt uuid; r content_library;
BEGIN
  SELECT id INTO bv FROM brand_voice WHERE is_active; SELECT id INTO icp FROM icp_profiles LIMIT 1;
  INSERT INTO core_assets (brand_voice_id, icp_profile_id, title, body_en) VALUES (bv, icp, 't', 'b') RETURNING id INTO ca;
  SELECT id INTO fs FROM format_specs WHERE format='text_post' AND channel='linkedin' AND language='en' AND is_active;
  INSERT INTO content_library (core_asset_id, format_spec_id, format, channel, language, body)
    VALUES (ca, fs, 'text_post','linkedin','en','x') RETURNING id INTO cid;
  PERFORM set_config('cmk.actor_type','human',true); PERFORM set_config('cmk.actor_name','Itay',true);
  UPDATE content_library SET status='approved', brand_score=80, icp_relevance_score=75, approved_by='Itay', approved_at=now() WHERE id=cid;
  SELECT * INTO r FROM content_library WHERE id=cid;
  IF r.approved_content_hash IS NULL OR r.edited_after_approval THEN RAISE EXCEPTION 'hash snapshot failed'; END IF;

  -- D2: edit after approval is allowed, flagged, approval kept
  PERFORM set_config('cmk.actor_type','agent',true);
  UPDATE content_library SET body='x edited' WHERE id=cid;
  SELECT * INTO r FROM content_library WHERE id=cid;
  IF r.status <> 'approved' OR NOT r.edited_after_approval THEN RAISE EXCEPTION 'D2 audit-only failed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM audit_log WHERE row_id=cid AND note LIKE 'edit_after_approval%') THEN RAISE EXCEPTION 'D2 audit row missing'; END IF;

  -- D3: timeout => unknown => no new attempt by agent
  INSERT INTO publish_instances (content_id, content_revision, sent_content_hash, channel, account_ref)
    VALUES (cid, 1, content_hash(r), 'linkedin', 'itay-profile') RETURNING id INTO pi;
  INSERT INTO publish_attempts (publish_instance_id, attempt_no) VALUES (pi, 1);
  UPDATE publish_attempts SET outcome='timeout', finished_at=now() WHERE publish_instance_id=pi AND attempt_no=1;
  IF (SELECT state FROM publish_instances WHERE id=pi) <> 'unknown' THEN RAISE EXCEPTION 'unknown state not set'; END IF;
  BEGIN
    INSERT INTO publish_attempts (publish_instance_id, attempt_no) VALUES (pi, 2);
    RAISE EXCEPTION 'resend gate did not fire';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'resend gate%' THEN RAISE; END IF; RAISE NOTICE 'D3 resend blocked ok'; END;
  BEGIN
    UPDATE publish_instances SET state='queued' WHERE id=pi;
    RAISE EXCEPTION 'agent resolve gate did not fire';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'agent resolve%' THEN RAISE; END IF; RAISE NOTICE 'D3 human-only ok'; END;
  PERFORM set_config('cmk.actor_type','human',true);
  UPDATE publish_instances SET state='confirmed', external_url='https://example.invalid/post', confirmed_by='Itay', confirmed_at=now() WHERE id=pi;

  -- work_items transitions
  PERFORM set_config('cmk.actor_type','agent',true);
  INSERT INTO work_items (kind, step, subject_table, subject_id, owner, max_attempts)
    VALUES ('derivative','repurpose','content_library',cid,'Repurposer',1) RETURNING id INTO w;
  UPDATE work_items SET state='running' WHERE id=w;
  UPDATE work_items SET state='awaiting_human', blocked_on='human_gate:approve_piece' WHERE id=w;
  BEGIN UPDATE work_items SET state='done' WHERE id=w; RAISE EXCEPTION 'human-only work gate did not fire';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'human-only work%' THEN RAISE; END IF; END;

  -- D5: agent may insert suggested only; cannot set payment
  INSERT INTO lead_threads (source_content_id, channel, conversation_ref) VALUES (cid, 'linkedin', 'comment-thread-ref') RETURNING id INTO lt;
  BEGIN UPDATE lead_threads SET payment_status='paid' WHERE id=lt; RAISE EXCEPTION 'lead gate did not fire';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'lead gate%' THEN RAISE; END IF; RAISE NOTICE 'D5 ok'; END;
  PERFORM set_config('cmk.actor_type','human',true);
  UPDATE lead_threads SET stage='new', confirmed_by='Itay', next_action='reply' WHERE id=lt;

  PERFORM 1 FROM volume_daily_v; PERFORM 1 FROM approval_queue_v; PERFORM 1 FROM usable_facts_v; PERFORM 1 FROM lead_handoff_v;
  RAISE NOTICE 'test_005 passed';
END $$;
