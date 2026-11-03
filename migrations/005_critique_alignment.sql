-- =============================================================================
-- CMK migration 005 — critique alignment (decisions D1–D5 locked 2026-11-03)
-- STATUS: DRAFT / SKETCH. Not applied to any live DB. Smoke-tested only in a
-- throwaway in-memory PGlite (see test_005.sql). Itay/runner applies it.
-- Applies on top of schema.sql + 002 + 003 + 004. Additive only. Idempotent.
--
-- What it adds:
--   §1  D2 audit-only edit tracking on approved content (NO freeze, NO revoke)
--   §2  work_items / work_transitions — Orchestrator state machine (plain Postgres)
--   §3  publish_instances / publish_attempts — D3: unknown => escalate, never auto-resend
--   §4  media_assets — rendered files + checksums for RenderQA
--   §5  lead_threads — D5: lead handoff inside CMK; agents can't touch proposal/payment
--   §6  memory kind / fact validity (ErrorWatcher classification, FactGate expiry)
--   §7  volume views — the 100/day definition (4 separate counters)
--   §8  audit coverage for new tables + wider watched columns; journal 'proposed'
--
-- Not here on purpose:
--   * NO approvals table and NO trigger that raises/revokes on edit (D2 = audit-only).
--   * Rules / templates / prompts stay in brand_voice / format_specs / prompt_versions (D4 = Postgres).
--   * No workflow engine (Temporal etc.); work_items is plain tables + a trigger.
--   * Google Calendar is a one-way VIEW; rotation_slots (+ publish_instances) is the schedule authority.
-- =============================================================================

BEGIN;
SET search_path = cmk, public;

-- -----------------------------------------------------------------------------
-- §1  D2 — approved content: audit-only edit tracking
-- -----------------------------------------------------------------------------
-- D2 TRADEOFF (Itay decision, 2026-11-03): edits to approved/scheduled/published
-- pieces are NOT blocked and do NOT cancel the approval. Risk accepted: an
-- approval can survive an edit, so what gets published may differ from what
-- Itay approved. Mitigations (visibility, not enforcement):
--   * approved_content_hash is captured at the moment of approval;
--   * any later change to the hashed fields sets edited_after_approval=true and
--     writes an audit_log row (action 'other', note 'edit_after_approval');
--   * publish_instances snapshot the hash actually sent (§3), so a mismatch with
--     approved_content_hash is queryable and is shown to Itay at confirm time.
-- Process guidance (agents.md): agents still make a NEW revision instead of editing.

CREATE OR REPLACE FUNCTION content_hash(p content_library) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT encode(digest(jsonb_build_object(
           'title', p.title, 'hook', p.hook, 'body', p.body, 'slides', p.slides,
           'payload', p.payload, 'media_refs', p.media_refs, 'cta', p.cta,
           'hashtags', to_jsonb(p.hashtags))::text, 'sha256'), 'hex')
$$;

ALTER TABLE content_library
  ADD COLUMN IF NOT EXISTS approved_content_hash    text,
  ADD COLUMN IF NOT EXISTS edited_after_approval    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS edited_after_approval_at timestamptz;

CREATE OR REPLACE FUNCTION track_edit_after_approval() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE h text := content_hash(NEW);
BEGIN
  IF (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved'
      AND OLD.status NOT IN ('scheduled','published'))
     OR (NEW.status IN ('approved','scheduled') AND NEW.approved_at IS DISTINCT FROM OLD.approved_at) THEN
    -- fresh approval, or Itay re-approves (new approved_at): snapshot what was approved
    NEW.approved_content_hash := h;
    NEW.edited_after_approval := false;
    NEW.edited_after_approval_at := NULL;
  ELSIF OLD.status IN ('approved','scheduled','published')
        AND OLD.approved_content_hash IS NOT NULL
        AND h IS DISTINCT FROM OLD.approved_content_hash
        AND NOT OLD.edited_after_approval THEN
    NEW.edited_after_approval := true;         -- flag only; approval is kept (D2)
    NEW.edited_after_approval_at := now();
    INSERT INTO audit_log (actor_type, actor_name, action, table_name, row_id,
                           old_status, new_status, run_id, note)
    VALUES (coalesce(nullif(current_setting('cmk.actor_type', true), ''), 'agent')::actor_type,
            nullif(current_setting('cmk.actor_name', true), ''), 'other', 'content_library', NEW.id,
            OLD.status, NEW.status, nullif(current_setting('cmk.run_id', true), ''),
            'edit_after_approval (D2: audit-only, approval retained)');
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS content_library_edit_after_approval ON content_library;
CREATE TRIGGER content_library_edit_after_approval BEFORE UPDATE ON content_library
  FOR EACH ROW EXECUTE FUNCTION track_edit_after_approval();

-- -----------------------------------------------------------------------------
-- §2  Orchestrator state machine (one row per unit of work, e.g. per derivative)
-- -----------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE work_state AS ENUM ('pending','running','awaiting_human','needs_changes',
                                  'done','failed','stopped');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS work_items (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind                text NOT NULL CHECK (kind IN ('core','derivative','render','package','publish','measure','ops')),
  step                text NOT NULL CHECK (step IN ('research','create_core','repurpose','spec_gate','fact_gate',
                        'editorial_review','human_approval','render','render_qa','package','schedule',
                        'publish','verify_publish','measure','lead_handoff','error_watch')),
  subject_table       text CHECK (subject_table IN ('core_assets','content_library','publish_instances',
                                                    'media_assets','rotation_slots','lead_threads')),
  subject_id          uuid,
  parent_work_item_id uuid REFERENCES work_items(id) ON DELETE SET NULL,
  state               work_state NOT NULL DEFAULT 'pending',
  owner               text NOT NULL,                 -- agent role, code module, or 'Itay'
  attempt_count       smallint NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  max_attempts        smallint NOT NULL DEFAULT 3 CHECK (max_attempts BETWEEN 1 AND 10),
  blocked_on          text,                          -- e.g. 'human_gate:approve_piece'
  stop_reason         text,
  last_error          text,
  lease_owner         text,                          -- one runner at a time; expired lease => resumable
  lease_until         timestamptz,
  run_id              text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (attempt_count <= max_attempts),
  CHECK (state NOT IN ('failed','stopped') OR stop_reason IS NOT NULL),
  CHECK (state <> 'awaiting_human' OR blocked_on IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS work_items_open    ON work_items (state, updated_at) WHERE state NOT IN ('done','failed','stopped');
CREATE INDEX IF NOT EXISTS work_items_subject ON work_items (subject_table, subject_id);
CREATE INDEX IF NOT EXISTS work_items_parent  ON work_items (parent_work_item_id);
-- One open item per (subject, step): a crash/restart resumes instead of duplicating.
CREATE UNIQUE INDEX IF NOT EXISTS work_items_one_open_per_step
  ON work_items (subject_table, subject_id, step) WHERE state NOT IN ('done','failed','stopped') AND subject_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS work_transitions (
  from_state  work_state NOT NULL,
  to_state    work_state NOT NULL,
  human_only  boolean NOT NULL DEFAULT false,
  PRIMARY KEY (from_state, to_state)
);
INSERT INTO work_transitions (from_state, to_state, human_only) VALUES
  ('pending','running',false), ('pending','stopped',false),
  ('running','done',false), ('running','needs_changes',false), ('running','awaiting_human',false),
  ('running','failed',false), ('running','pending',false),          -- pending = lease expired / retry
  ('needs_changes','running',false), ('needs_changes','stopped',false),
  ('awaiting_human','done',true), ('awaiting_human','needs_changes',true),
  ('awaiting_human','stopped',true), ('awaiting_human','pending',true),
  ('failed','pending',true), ('stopped','pending',true)              -- only Itay revives dead work
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION enforce_work_transition() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE t work_transitions;
        v_actor text := coalesce(nullif(current_setting('cmk.actor_type', true), ''), 'agent');
BEGIN
  NEW.updated_at := now();
  IF NEW.state IS DISTINCT FROM OLD.state THEN
    SELECT * INTO t FROM work_transitions WHERE from_state = OLD.state AND to_state = NEW.state;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'work_items: transition % -> % not allowed', OLD.state, NEW.state;
    END IF;
    IF t.human_only AND v_actor <> 'human' THEN
      RAISE EXCEPTION 'work_items: transition % -> % is human-only', OLD.state, NEW.state;
    END IF;
    IF NEW.state = 'running' THEN NEW.attempt_count := OLD.attempt_count + 1; END IF;
  END IF;
  RETURN NEW;   -- attempt_count > max_attempts fails the CHECK => Orchestrator must stop with a reason
END $$;
DROP TRIGGER IF EXISTS work_items_transition ON work_items;
CREATE TRIGGER work_items_transition BEFORE UPDATE ON work_items
  FOR EACH ROW EXECUTE FUNCTION enforce_work_transition();

-- -----------------------------------------------------------------------------
-- §3  Publish model — D3: unknown outcome => escalate to Itay, NEVER auto-resend
-- -----------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE publish_state AS ENUM ('queued','sending','confirmed','failed_retryable',
                                     'failed_final','unknown','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- One intended appearance of one piece revision on one account (optionally one slot).
-- Repeat publishes of approved library pieces are counted here (the "100/day" metric, §7).
CREATE TABLE IF NOT EXISTS publish_instances (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id          uuid NOT NULL REFERENCES content_library(id) ON DELETE RESTRICT,
  content_revision    integer NOT NULL,
  sent_content_hash   text NOT NULL,            -- content_hash() at send time; compare to approved_content_hash (D2)
  rotation_slot_id    uuid REFERENCES rotation_slots(id) ON DELETE RESTRICT,
  channel             channel_code NOT NULL,
  account_ref         text NOT NULL,            -- which profile/page; no secrets here
  mode                text NOT NULL DEFAULT 'manual' CHECK (mode IN ('manual','adapter')),
  state               publish_state NOT NULL DEFAULT 'queued',
  max_attempts        smallint NOT NULL DEFAULT 2 CHECK (max_attempts BETWEEN 1 AND 5),
  external_post_id    text,
  external_url        text,
  confirmed_by        text,                     -- 'Itay' or 'provider_lookup'
  confirmed_at        timestamptz,
  escalated_at        timestamptz,              -- set when state becomes unknown / failed_final
  resolved_by         text,                     -- human who resolved an unknown
  stop_reason         text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (state <> 'confirmed' OR (external_post_id IS NOT NULL OR external_url IS NOT NULL)),
  CHECK (state <> 'confirmed' OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)),
  CHECK (state NOT IN ('failed_final','cancelled') OR stop_reason IS NOT NULL)
);
-- Local dedupe only. These do NOT prove what happened at the provider.
CREATE UNIQUE INDEX IF NOT EXISTS publish_instances_one_per_slot
  ON publish_instances (content_id, account_ref, coalesce(rotation_slot_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE UNIQUE INDEX IF NOT EXISTS publish_instances_ext_post
  ON publish_instances (channel, external_post_id) WHERE external_post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS publish_instances_attention
  ON publish_instances (state, escalated_at) WHERE state IN ('unknown','failed_final');

CREATE TABLE IF NOT EXISTS publish_attempts (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(), -- also the provider idempotency key where supported
  publish_instance_id uuid NOT NULL REFERENCES publish_instances(id) ON DELETE RESTRICT,
  attempt_no          smallint NOT NULL CHECK (attempt_no >= 1),
  started_at          timestamptz NOT NULL DEFAULT now(),
  finished_at         timestamptz,
  outcome             text CHECK (outcome IN ('ok','error','timeout','unknown')),  -- NULL = in flight
  error_class         text CHECK (error_class IN ('auth','validation','rate_limit','provider_5xx','network','other')),
  provider_response   jsonb,                    -- trimmed; no tokens
  verified_via        text CHECK (verified_via IN ('provider_lookup','itay_manual')),
  UNIQUE (publish_instance_id, attempt_no)
);
CREATE UNIQUE INDEX IF NOT EXISTS publish_attempts_one_in_flight
  ON publish_attempts (publish_instance_id) WHERE outcome IS NULL;

-- Gate a new attempt: piece must be approved/scheduled; instance must be sendable.
-- D3: an instance in 'unknown' (or one that ever had a timeout/unknown attempt
-- not yet resolved by a human) can never get another attempt automatically.
CREATE OR REPLACE FUNCTION publish_attempt_gate() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE pi publish_instances; cl_status content_status;
BEGIN
  SELECT * INTO pi FROM publish_instances WHERE id = NEW.publish_instance_id FOR UPDATE;
  SELECT status INTO cl_status FROM content_library WHERE id = pi.content_id;
  IF cl_status NOT IN ('approved','scheduled') THEN
    RAISE EXCEPTION 'publish_attempts: content % is %, not approved/scheduled', pi.content_id, cl_status;
  END IF;
  IF pi.state NOT IN ('queued','failed_retryable') THEN
    RAISE EXCEPTION 'publish_attempts: instance % is % (D3: unknown => escalate to Itay, no resend)', pi.id, pi.state;
  END IF;
  IF NEW.attempt_no > pi.max_attempts THEN
    RAISE EXCEPTION 'publish_attempts: max_attempts % reached for %', pi.max_attempts, pi.id;
  END IF;
  UPDATE publish_instances SET state = 'sending', updated_at = now() WHERE id = pi.id;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS publish_attempts_gate ON publish_attempts;
CREATE TRIGGER publish_attempts_gate BEFORE INSERT ON publish_attempts
  FOR EACH ROW EXECUTE FUNCTION publish_attempt_gate();

-- Outcome => instance state. timeout/unknown => 'unknown' + escalate. Never re-queued here.
CREATE OR REPLACE FUNCTION publish_attempt_outcome() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.outcome IS NOT NULL AND OLD.outcome IS NULL THEN
    UPDATE publish_instances SET
      state = CASE NEW.outcome
                WHEN 'ok'    THEN 'sending'::publish_state     -- still needs confirmation (external id + confirmer)
                WHEN 'error' THEN CASE WHEN NEW.error_class IN ('rate_limit','provider_5xx','network')
                                       THEN 'failed_retryable'::publish_state ELSE 'failed_final'::publish_state END
                ELSE 'unknown'::publish_state END,
      escalated_at = CASE WHEN NEW.outcome IN ('timeout','unknown')
                            OR (NEW.outcome = 'error' AND NEW.error_class NOT IN ('rate_limit','provider_5xx','network'))
                          THEN now() ELSE escalated_at END,
      stop_reason = CASE WHEN NEW.outcome = 'error' AND NEW.error_class NOT IN ('rate_limit','provider_5xx','network')
                         THEN coalesce(stop_reason, 'provider error: ' || coalesce(NEW.error_class,'other')) ELSE stop_reason END,
      updated_at = now()
    WHERE id = NEW.publish_instance_id;
  ELSIF OLD.outcome IS NOT NULL AND NEW.outcome IS DISTINCT FROM OLD.outcome THEN
    RAISE EXCEPTION 'publish_attempts: outcome is write-once';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS publish_attempts_outcome ON publish_attempts;
CREATE TRIGGER publish_attempts_outcome AFTER UPDATE OF outcome ON publish_attempts
  FOR EACH ROW EXECUTE FUNCTION publish_attempt_outcome();

-- Instance transitions: leaving 'unknown' / 'failed_final' is human-only (D3).
-- A human may resolve unknown -> confirmed (it is live), cancelled, failed_final,
-- or explicitly re-queue it after checking (a human decision, never automatic).
CREATE OR REPLACE FUNCTION publish_instance_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_actor text := coalesce(nullif(current_setting('cmk.actor_type', true), ''), 'agent');
BEGIN
  IF OLD.state IN ('unknown','failed_final') AND NEW.state IS DISTINCT FROM OLD.state THEN
    IF v_actor <> 'human' THEN
      RAISE EXCEPTION 'publish_instances: leaving % is human-only (D3)', OLD.state;
    END IF;
    NEW.resolved_by := coalesce(NEW.resolved_by, nullif(current_setting('cmk.actor_name', true), ''), 'human');
  END IF;
  IF OLD.state = 'confirmed' AND NEW.state IS DISTINCT FROM OLD.state THEN
    RAISE EXCEPTION 'publish_instances: confirmed is terminal';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS publish_instances_guard ON publish_instances;
CREATE TRIGGER publish_instances_guard BEFORE UPDATE OF state ON publish_instances
  FOR EACH ROW EXECUTE FUNCTION publish_instance_guard();

-- -----------------------------------------------------------------------------
-- §4  media_assets — rendered files + checksums (RenderQA)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS media_assets (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id          uuid NOT NULL REFERENCES content_library(id) ON DELETE RESTRICT,
  content_revision    integer NOT NULL,
  kind                text NOT NULL CHECK (kind IN ('image','video','audio','pdf','subtitle')),
  storage_uri         text NOT NULL,            -- object storage / packages/<id>/r<rev>/media/...
  sha256              text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  bytes               bigint CHECK (bytes > 0),
  width               integer, height integer,
  duration_s          numeric(7,2), page_count integer,
  source              text NOT NULL CHECK (source IN ('own','stock','generated','screen_capture')),
  license_note        text,
  consent_fact_id     uuid REFERENCES approved_facts(id) ON DELETE RESTRICT,  -- likeness/voice (avatar)
  ai_disclosure       boolean NOT NULL DEFAULT false,
  render_work_item_id uuid REFERENCES work_items(id) ON DELETE SET NULL,
  qa_status           text NOT NULL DEFAULT 'pending' CHECK (qa_status IN ('pending','pass','fail')),
  qa_report           jsonb,                    -- RenderQA checks: count, dims, text-match, RTL, alt, subtitles
  qa_checked_at       timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (content_id, content_revision, storage_uri),
  CHECK (qa_status = 'pending' OR (qa_report IS NOT NULL AND qa_checked_at IS NOT NULL)),
  CHECK (source <> 'stock' OR license_note IS NOT NULL),
  CHECK (source <> 'generated' OR ai_disclosure)
);
CREATE INDEX IF NOT EXISTS media_assets_content ON media_assets (content_id, content_revision);

-- -----------------------------------------------------------------------------
-- §5  lead_threads — D5: lead handoff inside CMK
-- -----------------------------------------------------------------------------
-- Content agents never READ this table for content (B-12 analytics rule still
-- applies) and may only create 'suggested' rows / edit handoff fields.
-- proposal_* and payment_status are human-only (trigger below). No amounts,
-- prices or payment instruments are stored: payment_status is a coarse flag.
DO $$ BEGIN
  CREATE TYPE lead_stage AS ENUM ('suggested','new','replied','call_booked','proposal_sent',
                                  'won','lost','nurture','not_a_fit');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS lead_threads (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_content_id           uuid REFERENCES content_library(id) ON DELETE SET NULL,
  source_publish_instance_id  uuid REFERENCES publish_instances(id) ON DELETE SET NULL,
  channel                     channel_code,
  conversation_ref            text,             -- link/id of the DM/comment/call thread; no transcript here
  contact_label               text,             -- anonymized label set by Itay; no viewer analytics
  icp_profile_id              uuid REFERENCES icp_profiles(id) ON DELETE SET NULL,
  owner                       text NOT NULL DEFAULT 'Itay',
  stage                       lead_stage NOT NULL DEFAULT 'suggested',
  first_contact_at            timestamptz,
  next_action                 text,
  next_action_due             timestamptz,
  proposal_ref                text,             -- pointer to proposal doc (human-only)
  proposal_status             text NOT NULL DEFAULT 'none'
                                CHECK (proposal_status IN ('none','drafting','sent','accepted','declined')),
  payment_status              text NOT NULL DEFAULT 'none'
                                CHECK (payment_status IN ('none','pending','paid','n_a')),  -- human-only
  confirmed_by                text,             -- human who confirmed this is a real ICP conversation
  created_by                  actor_type NOT NULL DEFAULT 'agent',
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  CHECK (stage = 'suggested' OR confirmed_by IS NOT NULL),
  CHECK (stage IN ('suggested','won','lost','not_a_fit') OR next_action IS NOT NULL),
  CHECK (stage <> 'proposal_sent' OR proposal_ref IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS lead_threads_open ON lead_threads (owner, next_action_due)
  WHERE stage NOT IN ('won','lost','not_a_fit');

CREATE OR REPLACE FUNCTION lead_threads_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_actor text := coalesce(nullif(current_setting('cmk.actor_type', true), ''), 'agent');
BEGIN
  NEW.updated_at := now();
  IF v_actor <> 'human' THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.stage <> 'suggested' OR NEW.proposal_ref IS NOT NULL
         OR NEW.proposal_status <> 'none' OR NEW.payment_status <> 'none' OR NEW.confirmed_by IS NOT NULL THEN
        RAISE EXCEPTION 'lead_threads: agents may only insert suggested rows without proposal/payment/confirmation';
      END IF;
    ELSIF NEW.proposal_ref IS DISTINCT FROM OLD.proposal_ref
       OR NEW.proposal_status IS DISTINCT FROM OLD.proposal_status
       OR NEW.payment_status IS DISTINCT FROM OLD.payment_status
       OR NEW.confirmed_by IS DISTINCT FROM OLD.confirmed_by
       OR NEW.stage IS DISTINCT FROM OLD.stage
       OR NEW.owner IS DISTINCT FROM OLD.owner THEN
      RAISE EXCEPTION 'lead_threads: stage/owner/proposal/payment/confirmation are human-only (D5)';
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS lead_threads_guard ON lead_threads;
CREATE TRIGGER lead_threads_guard BEFORE INSERT OR UPDATE ON lead_threads
  FOR EACH ROW EXECUTE FUNCTION lead_threads_guard();

-- Handoff view for agents: no proposal/payment columns. When DB roles exist:
--   REVOKE ALL ON lead_threads FROM cmk_agent; GRANT SELECT ON lead_handoff_v TO cmk_agent;
CREATE OR REPLACE VIEW lead_handoff_v AS
  SELECT id, source_content_id, source_publish_instance_id, channel, conversation_ref,
         owner, stage, next_action, next_action_due, created_at, updated_at
  FROM lead_threads;

-- -----------------------------------------------------------------------------
-- §6  Memory kind + fact validity (D4: stays in Postgres rows)
-- -----------------------------------------------------------------------------
ALTER TABLE approved_facts
  ADD COLUMN IF NOT EXISTS last_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS valid_until      timestamptz,
  ADD COLUMN IF NOT EXISTS usage_scope      text[] NOT NULL DEFAULT '{public_posts}';

-- FactGate reads only this view: approved + public + not expired.
CREATE OR REPLACE VIEW usable_facts_v AS
  SELECT * FROM approved_facts
  WHERE status = 'approved' AND confidentiality = 'public'
    AND (valid_until IS NULL OR valid_until > now());

-- ErrorWatcher classification on each correction. Only policy-type kinds may be promoted.
ALTER TABLE correction_log
  ADD COLUMN IF NOT EXISTS memory_kind  text CHECK (memory_kind IN
      ('content_error','preference_once','policy_gap','fact_change','hypothesis','infra_failure')),
  ADD COLUMN IF NOT EXISTS rule_reason  text,
  ADD COLUMN IF NOT EXISTS rule_scope   jsonb,          -- {channels[], formats[], languages[], accounts[]}
  ADD COLUMN IF NOT EXISTS replay_report jsonb;         -- result of replay on past approved pieces / anti-examples
DO $$ BEGIN
  ALTER TABLE correction_log ADD CONSTRAINT correction_log_promotable_kind
    CHECK (promoted_to IS NULL OR memory_kind IS NULL OR memory_kind IN ('policy_gap','fact_change'));
  ALTER TABLE correction_log ADD CONSTRAINT correction_log_promotion_tested
    CHECK (promoted_to IS NULL OR memory_kind IS NULL OR (replay_report IS NOT NULL AND rule_reason IS NOT NULL));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- -----------------------------------------------------------------------------
-- §7  Volume — the "100/day" definition (Itay-default 2026-11-03, pending override)
-- -----------------------------------------------------------------------------
-- Four separate counters. The ~100/day SPEC goal is primarily (3) publish
-- instances via reuse + rotation, NOT 100 new cores/day. Days in Asia/Jerusalem.
CREATE OR REPLACE VIEW volume_daily_v AS
WITH d AS (
  SELECT (created_at AT TIME ZONE 'Asia/Jerusalem')::date AS day, 'new_families' AS metric FROM core_assets
  UNION ALL
  SELECT (created_at AT TIME ZONE 'Asia/Jerusalem')::date, 'new_derivatives' FROM content_library
  UNION ALL
  SELECT (confirmed_at AT TIME ZONE 'Asia/Jerusalem')::date, 'publish_instances' FROM publish_instances WHERE state = 'confirmed'
)
SELECT day,
       count(*) FILTER (WHERE metric = 'new_families')      AS new_families,
       count(*) FILTER (WHERE metric = 'new_derivatives')   AS new_derivatives,   -- includes recycle revisions
       count(*) FILTER (WHERE metric = 'publish_instances') AS publish_instances
FROM d GROUP BY day;

-- (4) items awaiting approval: a snapshot, not a daily flow.
CREATE OR REPLACE VIEW approval_queue_v AS
  SELECT 'core_assets' AS subject_table, id, created_at FROM core_assets WHERE status = 'in_review'
  UNION ALL SELECT 'content_library', id, created_at FROM content_library WHERE status = 'in_review'
  UNION ALL SELECT 'rotation_slots', id, created_at FROM rotation_slots WHERE status = 'filled'
  UNION ALL SELECT 'publish_instances', id, created_at FROM publish_instances WHERE state IN ('unknown','failed_final')
  UNION ALL SELECT 'lead_threads', id, created_at FROM lead_threads WHERE stage = 'suggested';

-- -----------------------------------------------------------------------------
-- §8  Audit coverage + journal vocabulary
-- -----------------------------------------------------------------------------
-- Widen the watched columns of 002's audit_status_change (state/stage + all hashed content fields).
CREATE OR REPLACE FUNCTION audit_status_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_actor actor_type := coalesce(nullif(current_setting('cmk.actor_type', true), ''), 'agent')::actor_type;
  v_name  text := nullif(current_setting('cmk.actor_name', true), '');
  v_run   text := nullif(current_setting('cmk.run_id', true), '');
  v_old   jsonb := CASE WHEN TG_OP = 'INSERT' THEN '{}'::jsonb ELSE to_jsonb(OLD) END;
  v_new   jsonb := CASE WHEN TG_OP = 'DELETE' THEN '{}'::jsonb ELSE to_jsonb(NEW) END;
  v_action text;
  v_changes jsonb := '{}'::jsonb;
  k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['status','state','stage','approved_by','approved_at','scheduled_at','published_at',
                           'brand_score','icp_relevance_score','is_active','external_url','body','payload',
                           'title','hook','slides','media_refs','cta','hashtags','owner','next_action',
                           'proposal_status','payment_status','qa_status','sha256','valid_until']
  LOOP
    IF (v_old -> k) IS DISTINCT FROM (v_new -> k) AND (v_old ? k OR v_new ? k) THEN
      v_changes := v_changes || jsonb_build_object(k, jsonb_build_array(v_old -> k, v_new -> k));
    END IF;
  END LOOP;

  IF TG_OP = 'UPDATE' AND v_changes = '{}'::jsonb THEN
    RETURN NEW;
  END IF;

  v_action := CASE
    WHEN TG_OP = 'INSERT' THEN 'insert'
    WHEN TG_OP = 'DELETE' THEN 'delete'
    WHEN v_new->>'status' = 'approved'  AND v_old->>'status' IS DISTINCT FROM 'approved'  THEN 'approve'
    WHEN v_new->>'status' = 'scheduled' AND v_old->>'status' IS DISTINCT FROM 'scheduled' THEN 'schedule'
    WHEN v_new->>'status' = 'published' AND v_old->>'status' IS DISTINCT FROM 'published' THEN 'publish'
    WHEN TG_TABLE_NAME = 'publish_instances' AND v_new->>'state' = 'confirmed'
         AND v_old->>'state' IS DISTINCT FROM 'confirmed' THEN 'publish'
    WHEN (v_old->>'status') IS DISTINCT FROM (v_new->>'status')
      OR (v_old->>'state')  IS DISTINCT FROM (v_new->>'state')
      OR (v_old->>'stage')  IS DISTINCT FROM (v_new->>'stage') THEN 'status_change'
    WHEN v_changes ? 'brand_score' OR v_changes ? 'icp_relevance_score' THEN 'guardian_check'
    WHEN TG_TABLE_NAME = 'prompt_versions' AND v_changes ? 'is_active' THEN 'prompt_activate'
    WHEN TG_TABLE_NAME = 'guardian_thresholds' THEN 'threshold_change'
    ELSE 'update'
  END;

  INSERT INTO audit_log (actor_type, actor_name, action, table_name, row_id,
                         old_status, new_status, changes, prompt_version_id, run_id)
  VALUES (v_actor, v_name, v_action, TG_TABLE_NAME,
          (coalesce(v_new->>'id', v_old->>'id'))::uuid,
          coalesce(v_old->>'status', v_old->>'state', v_old->>'stage'),
          coalesce(v_new->>'status', v_new->>'state', v_new->>'stage'),
          CASE WHEN TG_OP = 'UPDATE' THEN v_changes END,
          (coalesce(v_new->>'prompt_version_id', v_old->>'prompt_version_id'))::uuid,
          v_run);
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['work_items','publish_instances','publish_attempts','media_assets','lead_threads']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_audit', t);
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION audit_status_change()', t || '_audit', t);
  END LOOP;
END $$;

-- H-14: allow 'proposed' in the journal status vocabulary (entry J-20261103-012 used it).
ALTER TABLE cmk.agent_journal DROP CONSTRAINT IF EXISTS agent_journal_status_check;
ALTER TABLE cmk.agent_journal ADD CONSTRAINT agent_journal_status_check
  CHECK (status IN ('started','done','proposed','approved','rejected','blocked','failed'));

COMMIT;
