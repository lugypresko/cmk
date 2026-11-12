-- =============================================================================
-- CMK migration 012 — E2E chain slice (grill decisions G1–G14 locked 2026-11-04)
-- Renumbered from the local slice's 006. This branch already applied 006–011
-- (checklist, measurement, runtime, human boundaries, memory promotion, exact repeat).
-- STATUS: local PGlite only. Not hosted/prod.
-- Applies on top of schema.sql + 002..011. Additive only. Idempotent.
-- Does not replace 006–011 and does not enable auto-publish.
--
-- Closes (v0 depth) the chain gaps in /workspace/cmk-chain-gaps-2026-11-04.md:
--   §0  cmk_now() test clock (SET LOCAL cmk.now) so replays/demos can simulate time
--   §1  Brief / Ingest / Research stubs (G10: stub rows + reason, no full impl)
--   §2  work_items: chain steps, due_at, escalation (ops envelope)
--   §3  media_assets: RenderQA fields (G12: fix is proposed, Itay owns apply)
--   §4  approval_packages (+assets): hash = copy + assets + account + language +
--       repeat windows (G5, no first_comment); 48h timeout -> approval_stale (G11)
--   §5  publish verify states for manual LinkedIn (G7):
--       handed_for_paste -> reported_published(URL) -> verified (manual match confirm)
--       exact-repeat eligibility only after verified (G6)
--   §6  measurement: manual 24h/7d windows bound to a verified publish (G8)
--   §7  learning_proposals: drafts that need Itay approval (G8); nothing auto-applies
--   §8  lead_threads: draft-reply stub; no outbound without an approved draft (G9)
--   §9  ops_event_log (idempotent replay cursor for scripts/db_sync.mjs) + audit
--
-- Respects: D1 (code gates block, editorial scores only), D2 (copy edits stay
-- audit-only on content_library; but a PACKAGE hash is immutable once sent — a
-- change = new package revision + re-approval), D3 (no auto-resend; an unreported
-- hand-off escalates to Itay), D4 (rules in Postgres), D5 (lead_threads), D12
-- (exact repeat = same hash + asset checksums, blocked on edit / fact expiry).
-- =============================================================================

BEGIN;
SET search_path = cmk, public;

-- -----------------------------------------------------------------------------
-- §0  Test clock. Production: cmk.now unset => now(). Replays/demos: SET LOCAL cmk.now.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cmk_now() RETURNS timestamptz
LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('cmk.now', true), '')::timestamptz, now())
$$;

CREATE OR REPLACE FUNCTION cmk_actor() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('cmk.actor_type', true), ''), 'agent')
$$;

-- jsonb-canonical sha256 (jsonb::text output is the canonical serialisation;
-- cmk_ops/canon.py reproduces it byte-for-byte so Python and Postgres agree).
CREATE OR REPLACE FUNCTION package_hash(j jsonb) RETURNS text
LANGUAGE sql IMMUTABLE STRICT SET search_path = cmk, public AS $$
  SELECT encode(digest(convert_to(j::text, 'UTF8'), 'sha256'), 'hex')
$$;

-- -----------------------------------------------------------------------------
-- §1  Brief / Ingest / Research — v0 stubs (G10)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS business_briefs (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id         text NOT NULL,
  status         text NOT NULL DEFAULT 'stub' CHECK (status IN ('stub','draft','approved','retired')),
  who            text,            -- audience (ICP slug / role)
  pain           text,
  message        text,
  desired_action text,
  stub_reason    text,
  owner          text NOT NULL DEFAULT 'Itay',
  approved_by    text,
  journal_id     text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'stub' OR stub_reason IS NOT NULL),
  CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND who IS NOT NULL AND pain IS NOT NULL
                                  AND message IS NOT NULL AND desired_action IS NOT NULL)),
  UNIQUE (run_id)
);

CREATE TABLE IF NOT EXISTS ingest_sources (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id      text NOT NULL,
  kind        text NOT NULL CHECK (kind IN ('none','talk','recording','post','doc','note')),
  source_ref  text,               -- path / URL of existing content; no raw media here
  insights    jsonb NOT NULL DEFAULT '[]'::jsonb,
  status      text NOT NULL DEFAULT 'stub' CHECK (status IN ('stub','extracted','approved','retired')),
  stub_reason text,
  journal_id  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'stub' OR stub_reason IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS ingest_sources_run_kind ON ingest_sources (run_id, kind, coalesce(source_ref, ''));

CREATE TABLE IF NOT EXISTS research_notes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id      text NOT NULL,
  kind        text NOT NULL CHECK (kind IN ('content_evidence','past_posts','competitor_angles','missing_info','hook')),
  status      text NOT NULL DEFAULT 'stub' CHECK (status IN ('stub','draft','done')),
  summary     text,
  source_refs text[] NOT NULL DEFAULT '{}',
  changes_text boolean NOT NULL DEFAULT false,   -- if true it must finish before final Guardian + approval
  stub_reason text,
  journal_id  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'stub' OR stub_reason IS NOT NULL),
  UNIQUE (run_id, kind)
);

-- -----------------------------------------------------------------------------
-- §2  work_items — chain steps + ops envelope (owner, due, escalation, resume)
-- -----------------------------------------------------------------------------
ALTER TABLE work_items DROP CONSTRAINT IF EXISTS work_items_kind_check;
ALTER TABLE work_items ADD CONSTRAINT work_items_kind_check CHECK (kind IN
  ('core','derivative','render','package','publish','measure','ops','stub','learning','lead'));
ALTER TABLE work_items DROP CONSTRAINT IF EXISTS work_items_step_check;
ALTER TABLE work_items ADD CONSTRAINT work_items_step_check CHECK (step IN
  ('research','create_core','repurpose','spec_gate','fact_gate','editorial_review','human_approval',
   'render','render_qa','package','schedule','publish','verify_publish','measure','lead_handoff','error_watch',
   -- 012 additions
   'brief','ingest','copy_approval','art_direction','guardian_recheck','approval_package',
   'hand_for_paste','report_published','measure_24h','measure_7d','learning_proposal'));
ALTER TABLE work_items DROP CONSTRAINT IF EXISTS work_items_subject_table_check;
ALTER TABLE work_items ADD CONSTRAINT work_items_subject_table_check CHECK (subject_table IN
  ('core_assets','content_library','publish_instances','media_assets','rotation_slots','lead_threads',
   'approval_packages','business_briefs','ingest_sources','research_notes','performance_logs','learning_proposals'));

ALTER TABLE work_items
  ADD COLUMN IF NOT EXISTS step_key          text,          -- stable key inside a run, e.g. 'run001.render_qa'
  ADD COLUMN IF NOT EXISTS due_at            timestamptz,   -- e.g. approval due (48h)
  ADD COLUMN IF NOT EXISTS escalated_at      timestamptz,
  ADD COLUMN IF NOT EXISTS escalation_reason text,
  ADD COLUMN IF NOT EXISTS resume_hint       text,          -- the exact next command to resume
  ADD COLUMN IF NOT EXISTS is_stub           boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS work_items_run_step_key ON work_items (run_id, step_key) WHERE step_key IS NOT NULL;
DO $$ BEGIN
  ALTER TABLE work_items ADD CONSTRAINT work_items_escalation_reason
    CHECK (escalated_at IS NULL OR escalation_reason IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Escalation = hand to Itay with a reason. Never regenerates or resends (D3 spirit).
CREATE OR REPLACE FUNCTION escalate_work_item(p_id uuid, p_reason text) RETURNS void
LANGUAGE sql AS $$
  UPDATE work_items SET escalated_at = cmk_now(), escalation_reason = p_reason, owner = 'Itay'
  WHERE id = p_id AND escalated_at IS NULL
$$;

-- -----------------------------------------------------------------------------
-- §3  media_assets — RenderQA fields (G12)
-- -----------------------------------------------------------------------------
ALTER TABLE media_assets
  ADD COLUMN IF NOT EXISTS parent_asset_id uuid REFERENCES media_assets(id) ON DELETE RESTRICT, -- slide PNG -> its PDF
  ADD COLUMN IF NOT EXISTS page_index      integer CHECK (page_index >= 1),
  ADD COLUMN IF NOT EXISTS language        lang_code,
  ADD COLUMN IF NOT EXISTS renderer        text,      -- e.g. 'cmk_ops.carousel/chrome-headless'
  ADD COLUMN IF NOT EXISTS template_id     text,      -- deterministic local template
  ADD COLUMN IF NOT EXISTS template_sha256 text,
  ADD COLUMN IF NOT EXISTS source_sha256   text,      -- sha256 of the slide text input
  ADD COLUMN IF NOT EXISTS qa_version      text,
  ADD COLUMN IF NOT EXISTS qa_failures     integer NOT NULL DEFAULT 0 CHECK (qa_failures >= 0),
  ADD COLUMN IF NOT EXISTS qa_warnings     integer NOT NULL DEFAULT 0 CHECK (qa_warnings >= 0),
  ADD COLUMN IF NOT EXISTS fix_proposal    jsonb,     -- RenderQA proposes; it never applies
  ADD COLUMN IF NOT EXISTS fix_owner       text NOT NULL DEFAULT 'Itay',
  ADD COLUMN IF NOT EXISTS fix_status      text NOT NULL DEFAULT 'none'
                             CHECK (fix_status IN ('none','proposed','applied','rejected'));
DO $$ BEGIN
  ALTER TABLE media_assets ADD CONSTRAINT media_assets_qa_pass_clean
    CHECK (qa_status <> 'pass' OR qa_failures = 0);
  ALTER TABLE media_assets ADD CONSTRAINT media_assets_qa_fail_has_fix
    CHECK (qa_status <> 'fail' OR (qa_failures > 0 AND fix_proposal IS NOT NULL AND fix_status <> 'none'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION media_assets_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.sha256 IS DISTINCT FROM OLD.sha256 OR NEW.storage_uri IS DISTINCT FROM OLD.storage_uri THEN
    RAISE EXCEPTION 'media_assets: file identity is immutable; a re-render is a new row';
  END IF;
  IF OLD.qa_status <> 'pending' AND NEW.qa_status IS DISTINCT FROM OLD.qa_status THEN
    RAISE EXCEPTION 'media_assets: qa_status % is final for this file; re-render => new asset row', OLD.qa_status;
  END IF;
  IF NEW.fix_status IN ('applied','rejected') AND NEW.fix_status IS DISTINCT FROM OLD.fix_status
     AND cmk_actor() <> 'human' THEN
    RAISE EXCEPTION 'media_assets: applying/rejecting a RenderQA fix is human-only (G12: Itay owns apply)';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS media_assets_guard ON media_assets;
CREATE TRIGGER media_assets_guard BEFORE UPDATE ON media_assets
  FOR EACH ROW EXECUTE FUNCTION media_assets_guard();

-- -----------------------------------------------------------------------------
-- §4  approval_packages — the thing Itay approves (G5, G11)
-- -----------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE approval_package_state AS ENUM ('draft','qa_blocked','awaiting_approval','approved',
                                              'changes_requested','approval_stale','superseded');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS approval_packages (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id                text NOT NULL,
  package_key           text NOT NULL,                -- e.g. 'run001.linkedin.he.text+carousel'
  revision              integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  content_id            uuid NOT NULL REFERENCES content_library(id) ON DELETE RESTRICT,  -- the copy piece
  channel               channel_code NOT NULL,
  account_ref           text NOT NULL,
  language              lang_code NOT NULL,
  repeat_windows        jsonb NOT NULL,
  manifest              jsonb NOT NULL,               -- human-readable package (not all hashed)
  hash_input            jsonb NOT NULL,               -- exactly what package_hash covers
  package_hash          text NOT NULL CHECK (package_hash ~ '^[0-9a-f]{64}$'),
  state                 approval_package_state NOT NULL DEFAULT 'draft',
  approver              text NOT NULL DEFAULT 'Itay',
  sent_for_approval_at  timestamptz,
  approval_due_at       timestamptz,                  -- sent + 48h (trigger)
  approved_by           text,
  approved_at           timestamptz,
  approved_hash         text,
  decision_note         text,
  stale_at              timestamptz,
  exact_repeat_eligible boolean NOT NULL DEFAULT false,
  exact_repeat_marked_at timestamptz,
  verified_publish_instance_id uuid,                  -- FK added in §5
  superseded_by         uuid REFERENCES approval_packages(id) ON DELETE RESTRICT,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (package_key, revision),
  -- G5: the hash is over these five parts, and it is reproducible from hash_input
  CHECK (hash_input ?& ARRAY['copy','assets','account','language','repeat_windows']),
  CHECK (package_hash = package_hash(hash_input)),
  CHECK (hash_input->'account'->>'account_ref' = account_ref AND hash_input->'account'->>'channel' = channel::text
         AND hash_input->>'language' = language::text AND hash_input->'repeat_windows' = repeat_windows),
  -- G5: NO first_comment in v0, anywhere in the package
  CHECK (NOT (manifest ? 'first_comment') AND NOT (coalesce(manifest->'copy','{}'::jsonb) ? 'first_comment')
         AND NOT (hash_input->'copy' ? 'first_comment')),
  CHECK (jsonb_typeof(hash_input->'assets') = 'array'),
  CHECK (state <> 'awaiting_approval' OR (sent_for_approval_at IS NOT NULL AND approval_due_at IS NOT NULL)),
  CHECK (state <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL AND approved_hash = package_hash)),
  CHECK (state <> 'approval_stale' OR stale_at IS NOT NULL),
  CHECK (NOT exact_repeat_eligible OR (state = 'approved' AND verified_publish_instance_id IS NOT NULL
                                        AND exact_repeat_marked_at IS NOT NULL)),
  CHECK (repeat_windows ? 'mode' AND repeat_windows->>'mode' IN ('none','exact_repeat'))
);
CREATE INDEX IF NOT EXISTS approval_packages_waiting ON approval_packages (approval_due_at) WHERE state = 'awaiting_approval';

CREATE TABLE IF NOT EXISTS approval_package_assets (
  package_id     uuid NOT NULL REFERENCES approval_packages(id) ON DELETE RESTRICT,
  media_asset_id uuid NOT NULL REFERENCES media_assets(id) ON DELETE RESTRICT,
  role           text NOT NULL CHECK (role IN ('carousel_pdf','image','video','subtitle')),
  position       smallint NOT NULL DEFAULT 1,
  sha256         text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  PRIMARY KEY (package_id, media_asset_id)
);

CREATE OR REPLACE FUNCTION approval_package_assets_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE m media_assets; p approval_packages;
BEGIN
  SELECT * INTO m FROM media_assets WHERE id = NEW.media_asset_id;
  SELECT * INTO p FROM approval_packages WHERE id = NEW.package_id;
  IF m.sha256 <> NEW.sha256 THEN
    RAISE EXCEPTION 'approval_package_assets: sha256 snapshot % != media_assets.sha256 %', NEW.sha256, m.sha256;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p.hash_input->'assets') a WHERE a->>'sha256' = NEW.sha256) THEN
    RAISE EXCEPTION 'approval_package_assets: asset % is not covered by the package hash', NEW.sha256;
  END IF;
  IF p.state NOT IN ('draft','qa_blocked') THEN
    RAISE EXCEPTION 'approval_package_assets: package % is %, assets are frozen (new revision instead)', p.id, p.state;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS approval_package_assets_guard ON approval_package_assets;
CREATE TRIGGER approval_package_assets_guard BEFORE INSERT OR UPDATE ON approval_package_assets
  FOR EACH ROW EXECUTE FUNCTION approval_package_assets_guard();

CREATE TABLE IF NOT EXISTS approval_package_transitions (
  from_state approval_package_state NOT NULL,
  to_state   approval_package_state NOT NULL,
  human_only boolean NOT NULL DEFAULT false,
  PRIMARY KEY (from_state, to_state)
);
INSERT INTO approval_package_transitions VALUES
  ('draft','qa_blocked',false), ('qa_blocked','superseded',false),
  ('draft','awaiting_approval',false),
  ('awaiting_approval','approved',true), ('awaiting_approval','changes_requested',true),
  ('awaiting_approval','approval_stale',false),           -- only via timeout (checked below)
  ('awaiting_approval','superseded',false),
  ('approval_stale','awaiting_approval',true),            -- Itay asks to re-send; new 48h window
  ('approval_stale','superseded',false),
  ('changes_requested','superseded',false),
  ('approved','superseded',true),
  ('draft','superseded',false)
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION approval_package_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE t approval_package_transitions; bad int;
BEGIN
  NEW.updated_at := now();
  IF TG_OP = 'INSERT' THEN
    IF NEW.state NOT IN ('draft','qa_blocked') THEN
      RAISE EXCEPTION 'approval_packages: new packages start as draft/qa_blocked';
    END IF;
    RETURN NEW;
  END IF;
  -- Frozen once sent: no hash/manifest/account/repeat edits; a change is a new revision (re-approve).
  IF OLD.state NOT IN ('draft','qa_blocked')
     AND (NEW.package_hash IS DISTINCT FROM OLD.package_hash OR NEW.hash_input IS DISTINCT FROM OLD.hash_input
          OR NEW.account_ref IS DISTINCT FROM OLD.account_ref OR NEW.repeat_windows IS DISTINCT FROM OLD.repeat_windows
          OR NEW.content_id IS DISTINCT FROM OLD.content_id) THEN
    RAISE EXCEPTION 'approval_packages: package % is %, content is frozen; build a new revision and re-approve', OLD.id, OLD.state;
  END IF;
  IF NEW.state IS DISTINCT FROM OLD.state THEN
    SELECT * INTO t FROM approval_package_transitions WHERE from_state = OLD.state AND to_state = NEW.state;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'approval_packages: % -> % not allowed', OLD.state, NEW.state;
    END IF;
    IF t.human_only AND cmk_actor() <> 'human' THEN
      RAISE EXCEPTION 'approval_packages: % -> % is human-only', OLD.state, NEW.state;
    END IF;
    IF NEW.state = 'awaiting_approval' THEN
      NEW.sent_for_approval_at := cmk_now();
      NEW.approval_due_at := cmk_now() + interval '48 hours';    -- G11
      NEW.stale_at := NULL;
      -- every hashed asset must exist, be linked, and have passed RenderQA
      SELECT count(*) INTO bad FROM jsonb_array_elements(NEW.hash_input->'assets') a
       WHERE NOT EXISTS (SELECT 1 FROM approval_package_assets pa JOIN media_assets m ON m.id = pa.media_asset_id
                          WHERE pa.package_id = NEW.id AND pa.sha256 = a->>'sha256' AND m.qa_status = 'pass');
      IF bad > 0 THEN
        RAISE EXCEPTION 'approval_packages: % hashed asset(s) missing or not RenderQA pass; cannot send for approval', bad;
      END IF;
    END IF;
    IF NEW.state = 'approval_stale' THEN
      IF cmk_now() < OLD.approval_due_at THEN
        RAISE EXCEPTION 'approval_packages: not stale before approval_due_at %', OLD.approval_due_at;
      END IF;
      NEW.stale_at := cmk_now();
    END IF;
    IF NEW.state = 'approved' THEN
      IF cmk_now() >= OLD.approval_due_at THEN
        RAISE EXCEPTION 'approval_packages: approval window expired at % (G11: mark stale, re-send, no late/auto approve)', OLD.approval_due_at;
      END IF;
      NEW.approved_at := coalesce(NEW.approved_at, cmk_now());
      NEW.approved_by := coalesce(NEW.approved_by, nullif(current_setting('cmk.actor_name', true), ''));
      IF NEW.approved_hash IS DISTINCT FROM OLD.package_hash THEN
        RAISE EXCEPTION 'approval_packages: approved_hash must equal package_hash (approver confirms the exact hash)';
      END IF;
    END IF;
  END IF;
  -- G6: exact-repeat only after a VERIFIED publish of this exact hash
  IF NEW.exact_repeat_eligible AND NOT OLD.exact_repeat_eligible THEN
    IF NOT EXISTS (SELECT 1 FROM publish_instances pi
                    WHERE pi.id = NEW.verified_publish_instance_id AND pi.approval_package_id = NEW.id
                      AND pi.manual_state = 'verified' AND pi.sent_content_hash = NEW.package_hash) THEN
      RAISE EXCEPTION 'approval_packages: exact_repeat requires a verified publish of hash % (G6)', NEW.package_hash;
    END IF;
    NEW.exact_repeat_marked_at := coalesce(NEW.exact_repeat_marked_at, cmk_now());
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS approval_package_guard ON approval_packages;
CREATE TRIGGER approval_package_guard BEFORE INSERT OR UPDATE ON approval_packages
  FOR EACH ROW EXECUTE FUNCTION approval_package_guard();

-- Sweep: awaiting_approval past due -> approval_stale. Never approves anything (G11).
CREATE OR REPLACE FUNCTION mark_stale_approvals() RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  UPDATE approval_packages SET state = 'approval_stale'
   WHERE state = 'awaiting_approval' AND approval_due_at <= cmk_now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

-- -----------------------------------------------------------------------------
-- §5  Publish verification for manual LinkedIn (G7, G14) + exact repeat (G6)
-- -----------------------------------------------------------------------------
ALTER TABLE publish_instances
  ADD COLUMN IF NOT EXISTS approval_package_id uuid REFERENCES approval_packages(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS manual_state   text CHECK (manual_state IN
                             ('handed_for_paste','reported_published','verified','verify_mismatch')),
  ADD COLUMN IF NOT EXISTS handed_at      timestamptz,
  ADD COLUMN IF NOT EXISTS handed_by      text,
  ADD COLUMN IF NOT EXISTS reported_url   text,
  ADD COLUMN IF NOT EXISTS reported_at    timestamptz,
  ADD COLUMN IF NOT EXISTS reported_by    text,
  ADD COLUMN IF NOT EXISTS verified_at    timestamptz,
  ADD COLUMN IF NOT EXISTS verified_by    text,
  ADD COLUMN IF NOT EXISTS verify_checklist jsonb,     -- {text_matches, assets_match, account_matches, url_opens}
  ADD COLUMN IF NOT EXISTS live_text_sha256 text,      -- optional: normalised hash of text Itay pasted back
  ADD COLUMN IF NOT EXISTS is_exact_repeat boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS repeat_of_publish_instance_id uuid REFERENCES publish_instances(id) ON DELETE RESTRICT;
DO $$ BEGIN
  ALTER TABLE approval_packages ADD CONSTRAINT approval_packages_verified_pi_fk
    FOREIGN KEY (verified_publish_instance_id) REFERENCES publish_instances(id) ON DELETE RESTRICT;
  ALTER TABLE publish_instances ADD CONSTRAINT publish_instances_manual_confirm_needs_verify
    CHECK (approval_package_id IS NULL OR state <> 'confirmed' OR manual_state = 'verified');
  ALTER TABLE publish_instances ADD CONSTRAINT publish_instances_reported_url
    CHECK (manual_state NOT IN ('reported_published','verified','verify_mismatch')
           OR (reported_url ~ '^https://(www\.)?linkedin\.com/(posts|feed/update)/' AND reported_at IS NOT NULL));
  ALTER TABLE publish_instances ADD CONSTRAINT publish_instances_verified_fields
    CHECK (manual_state <> 'verified' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL
           AND verify_checklist IS NOT NULL AND external_url = reported_url));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION publish_manual_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE p approval_packages; ok boolean;
BEGIN
  IF NEW.approval_package_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO p FROM approval_packages WHERE id = NEW.approval_package_id;
  IF TG_OP = 'INSERT' THEN
    IF p.state <> 'approved' THEN
      RAISE EXCEPTION 'publish_instances: package % is %, not approved (no hand-off)', p.id, p.state;
    END IF;
    IF NEW.sent_content_hash IS DISTINCT FROM p.approved_hash THEN
      RAISE EXCEPTION 'publish_instances: sent hash % != approved package hash %', NEW.sent_content_hash, p.approved_hash;
    END IF;
    IF NEW.mode <> 'manual' OR NEW.manual_state IS DISTINCT FROM 'handed_for_paste' OR NEW.handed_at IS NULL THEN
      RAISE EXCEPTION 'publish_instances: v0 LinkedIn is manual; start at handed_for_paste with handed_at (G14)';
    END IF;
    IF NEW.is_exact_repeat AND NOT p.exact_repeat_eligible THEN
      RAISE EXCEPTION 'publish_instances: exact repeat blocked; package % not marked after a verified publish (G6)', p.id;
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.manual_state IS DISTINCT FROM OLD.manual_state THEN
    IF NOT ((OLD.manual_state = 'handed_for_paste'   AND NEW.manual_state = 'reported_published')
         OR (OLD.manual_state = 'reported_published' AND NEW.manual_state IN ('verified','verify_mismatch'))
         OR (OLD.manual_state = 'verify_mismatch'    AND NEW.manual_state = 'reported_published')) THEN
      RAISE EXCEPTION 'publish_instances: manual % -> % not allowed', OLD.manual_state, NEW.manual_state;
    END IF;
    IF cmk_actor() <> 'human' THEN
      RAISE EXCEPTION 'publish_instances: % is reported/confirmed by Itay only (no LinkedIn scrape, G7)', NEW.manual_state;
    END IF;
    IF NEW.manual_state = 'verified' THEN
      SELECT coalesce(bool_and(v::boolean), false) INTO ok
        FROM jsonb_each_text(NEW.verify_checklist) AS e(k, v)
       WHERE k IN ('text_matches','assets_match','account_matches','url_opens');
      IF NOT ok OR NOT (NEW.verify_checklist ?& ARRAY['text_matches','assets_match','account_matches','url_opens']) THEN
        RAISE EXCEPTION 'publish_instances: verify needs all four manual match checks true (URL alone != content match)';
      END IF;
      NEW.verified_at := coalesce(NEW.verified_at, cmk_now());
    END IF;
  END IF;
  IF OLD.manual_state = 'verified' AND (NEW.verify_checklist IS DISTINCT FROM OLD.verify_checklist
                                        OR NEW.reported_url IS DISTINCT FROM OLD.reported_url) THEN
    RAISE EXCEPTION 'publish_instances: verified is terminal';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS publish_manual_guard ON publish_instances;
CREATE TRIGGER publish_manual_guard BEFORE INSERT OR UPDATE ON publish_instances
  FOR EACH ROW EXECUTE FUNCTION publish_manual_guard();

-- What Itay must look at right now (ops envelope view).
CREATE OR REPLACE VIEW publish_attention_v AS
  SELECT id, approval_package_id, manual_state, handed_at, reported_at,
         CASE WHEN manual_state = 'handed_for_paste' AND handed_at < cmk_now() - interval '24 hours'
                THEN 'escalate: handed >24h, no URL reported (D3: never auto-resend)'
              WHEN manual_state = 'reported_published' THEN 'Itay: open URL, confirm match -> verify'
              WHEN manual_state = 'verify_mismatch' THEN 'Itay: fix live post or re-report; no repeat'
         END AS attention
  FROM publish_instances
  WHERE approval_package_id IS NOT NULL AND manual_state IN ('handed_for_paste','reported_published','verify_mismatch');

-- -----------------------------------------------------------------------------
-- §6  Measurement — manual fixed windows on a verified publish (G8)
-- -----------------------------------------------------------------------------
ALTER TABLE performance_logs
  ADD COLUMN IF NOT EXISTS publish_instance_id  uuid REFERENCES publish_instances(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS substantive_comments integer CHECK (substantive_comments >= 0),
  ADD COLUMN IF NOT EXISTS inbound_dms          integer CHECK (inbound_dms >= 0),
  ADD COLUMN IF NOT EXISTS entered_by           text,
  ADD COLUMN IF NOT EXISTS baseline_ref         text;      -- which past post/median this is compared to
CREATE UNIQUE INDEX IF NOT EXISTS performance_logs_pi_window
  ON performance_logs (publish_instance_id, window_label) WHERE publish_instance_id IS NOT NULL;

CREATE OR REPLACE FUNCTION performance_window_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE pi publish_instances; need interval;
BEGIN
  IF NEW.publish_instance_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO pi FROM publish_instances WHERE id = NEW.publish_instance_id;
  IF pi.manual_state IS DISTINCT FROM 'verified' THEN
    RAISE EXCEPTION 'performance_logs: publish % is %, measure only verified publishes', pi.id, pi.manual_state;
  END IF;
  IF NEW.window_label NOT IN ('24h','7d') THEN
    RAISE EXCEPTION 'performance_logs: v0 manual windows are 24h and 7d only';
  END IF;
  need := CASE NEW.window_label WHEN '24h' THEN interval '24 hours' ELSE interval '7 days' END;
  IF NEW.captured_at < coalesce(pi.reported_at, pi.verified_at) + need THEN
    RAISE EXCEPTION 'performance_logs: % window not reached (published % + %)', NEW.window_label, pi.reported_at, need;
  END IF;
  IF NEW.source <> 'manual' OR NEW.entered_by IS NULL THEN
    RAISE EXCEPTION 'performance_logs: v0 measurement is manual and needs entered_by';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS performance_window_guard ON performance_logs;
CREATE TRIGGER performance_window_guard BEFORE INSERT OR UPDATE ON performance_logs
  FOR EACH ROW EXECUTE FUNCTION performance_window_guard();

-- -----------------------------------------------------------------------------
-- §7  Learning proposals — drafts only; Itay approves; applying is a separate human act
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS learning_proposals (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id              text NOT NULL,
  approval_package_id uuid REFERENCES approval_packages(id) ON DELETE SET NULL,
  performance_log_ids uuid[] NOT NULL DEFAULT '{}',
  target              text NOT NULL CHECK (target IN ('brand_voice','format_specs','prompt_versions',
                                                       'guardian_rules','scheduler','hook_type','none')),
  proposal            text NOT NULL,
  evidence            jsonb NOT NULL DEFAULT '{}'::jsonb,
  memory_kind         text CHECK (memory_kind IN ('hypothesis','policy_gap','preference_once','fact_change')),
  status              memory_status NOT NULL DEFAULT 'draft',
  approved_by         text,
  approved_at         timestamptz,
  applied_ref         text,            -- set by a human when the change is actually made elsewhere
  created_by          actor_type NOT NULL DEFAULT 'agent',
  created_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CHECK (applied_ref IS NULL OR status = 'approved')
);
CREATE OR REPLACE FUNCTION learning_proposals_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status <> 'draft' THEN
    RAISE EXCEPTION 'learning_proposals: proposals start as draft';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.status IS DISTINCT FROM OLD.status OR NEW.applied_ref IS DISTINCT FROM OLD.applied_ref)
     AND cmk_actor() <> 'human' THEN
    RAISE EXCEPTION 'learning_proposals: approve/apply is human-only (G8)';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS learning_proposals_guard ON learning_proposals;
CREATE TRIGGER learning_proposals_guard BEFORE INSERT OR UPDATE ON learning_proposals
  FOR EACH ROW EXECUTE FUNCTION learning_proposals_guard();

-- -----------------------------------------------------------------------------
-- §8  LeadOps stub — no outbound without an approved draft (G9, D5)
-- -----------------------------------------------------------------------------
ALTER TABLE lead_threads
  ADD COLUMN IF NOT EXISTS draft_reply       text,
  ADD COLUMN IF NOT EXISTS draft_status      text NOT NULL DEFAULT 'none'
                             CHECK (draft_status IN ('none','draft','approved','rejected','sent_by_itay')),
  ADD COLUMN IF NOT EXISTS draft_approved_by text,
  ADD COLUMN IF NOT EXISTS draft_sha256      text,     -- what Itay approved; send must match
  ADD COLUMN IF NOT EXISTS outbound_sent_at  timestamptz,
  ADD COLUMN IF NOT EXISTS sla_due_at        timestamptz;
DO $$ BEGIN
  ALTER TABLE lead_threads ADD CONSTRAINT lead_threads_outbound_needs_approved_draft
    CHECK (outbound_sent_at IS NULL OR (draft_status = 'sent_by_itay' AND draft_approved_by IS NOT NULL));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION lead_threads_draft_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.draft_status NOT IN ('none','draft') THEN
      RAISE EXCEPTION 'lead_threads: drafts start as none/draft';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.draft_status IS DISTINCT FROM OLD.draft_status THEN
    IF NEW.draft_status IN ('approved','rejected','sent_by_itay') AND cmk_actor() <> 'human' THEN
      RAISE EXCEPTION 'lead_threads: draft % is human-only (G9)', NEW.draft_status;
    END IF;
    IF NEW.draft_status = 'sent_by_itay' AND OLD.draft_status <> 'approved' THEN
      RAISE EXCEPTION 'lead_threads: no outbound without an approved draft (G9)';
    END IF;
    IF NEW.draft_status = 'approved' THEN
      NEW.draft_sha256 := encode(digest(convert_to(coalesce(NEW.draft_reply, ''), 'UTF8'), 'sha256'), 'hex');
    END IF;
  END IF;
  IF OLD.draft_status IN ('approved','sent_by_itay') AND NEW.draft_reply IS DISTINCT FROM OLD.draft_reply THEN
    RAISE EXCEPTION 'lead_threads: approved draft text is frozen; write a new draft';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS lead_threads_draft_guard ON lead_threads;
CREATE TRIGGER lead_threads_draft_guard BEFORE INSERT OR UPDATE ON lead_threads
  FOR EACH ROW EXECUTE FUNCTION lead_threads_draft_guard();

-- -----------------------------------------------------------------------------
-- §9  Replay cursor + audit coverage
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ops_event_log (
  run_id      text NOT NULL,
  seq         integer NOT NULL,
  event       text NOT NULL,
  event_ts    timestamptz NOT NULL,
  actor_type  actor_type NOT NULL,
  actor_name  text,
  payload_sha256 text NOT NULL,
  applied_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_id, seq)
);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['approval_packages','business_briefs','ingest_sources','research_notes','learning_proposals']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_audit', t);
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION audit_status_change()', t || '_audit', t);
  END LOOP;
END $$;

-- approval queue now includes packages (and stale ones, which need Itay to re-send or drop)
CREATE OR REPLACE VIEW approval_queue_v AS
  SELECT 'core_assets' AS subject_table, id, created_at FROM core_assets WHERE status = 'in_review'
  UNION ALL SELECT 'content_library', id, created_at FROM content_library WHERE status = 'in_review'
  UNION ALL SELECT 'rotation_slots', id, created_at FROM rotation_slots WHERE status = 'filled'
  UNION ALL SELECT 'publish_instances', id, created_at FROM publish_instances WHERE state IN ('unknown','failed_final')
  UNION ALL SELECT 'lead_threads', id, created_at FROM lead_threads WHERE stage = 'suggested'
  UNION ALL SELECT 'approval_packages', id, created_at FROM approval_packages WHERE state IN ('awaiting_approval','approval_stale');

COMMIT;
