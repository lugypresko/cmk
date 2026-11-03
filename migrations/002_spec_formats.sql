-- =============================================================================
-- CMK migration 002 — SPEC v1.0 formats, 14-day rotation, audit_log, prompt_versions
-- Applies on top of schema.sql (v0). Additive only: no column/constraint/enum
-- value from schema.sql is dropped, renamed or loosened.
--
-- Run:  psql -v ON_ERROR_STOP=1 -f migrations/002_spec_formats.sql
--
-- Part A adds enum values. PostgreSQL can't use a new enum value inside the
-- transaction that created it, so Part A commits before Part B uses the values.
-- Every statement is idempotent (IF NOT EXISTS) so a failed Part B can be re-run.
-- =============================================================================

SET search_path = cmk, public;

-- -----------------------------------------------------------------------------
-- PART A — enum values (own transaction)
-- -----------------------------------------------------------------------------
BEGIN;

-- SPEC formats. With v0 'text_post' + 'carousel' these are the 11 SPEC formats.
-- v0 placeholders 'thread', 'short_video_script', 'article' stay in the enum
-- (Postgres can't drop enum values safely) and are marked legacy in
-- format_registry below: thread -> x_thread, short_video_script -> reel.
ALTER TYPE format_code ADD VALUE IF NOT EXISTS 'broll';
ALTER TYPE format_code ADD VALUE IF NOT EXISTS 'x_thread';
ALTER TYPE format_code ADD VALUE IF NOT EXISTS 'reel';
ALTER TYPE format_code ADD VALUE IF NOT EXISTS 'short';
ALTER TYPE format_code ADD VALUE IF NOT EXISTS 'infographic';
ALTER TYPE format_code ADD VALUE IF NOT EXISTS 'poll';
ALTER TYPE format_code ADD VALUE IF NOT EXISTS 'interactive_story';
ALTER TYPE format_code ADD VALUE IF NOT EXISTS 'email';
ALTER TYPE format_code ADD VALUE IF NOT EXISTS 'avatar';

-- Channels needed by the new formats (short -> YouTube Shorts, email -> newsletter).
ALTER TYPE channel_code ADD VALUE IF NOT EXISTS 'youtube';
ALTER TYPE channel_code ADD VALUE IF NOT EXISTS 'email';

COMMIT;

-- -----------------------------------------------------------------------------
-- PART B — tables, columns, triggers
-- -----------------------------------------------------------------------------
BEGIN;
SET search_path = cmk, public;

-- New enums (created fresh, so usable in this transaction).
DO $$ BEGIN
  CREATE TYPE media_kind AS ENUM ('text', 'image', 'video', 'interactive', 'email');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE rotation_status AS ENUM ('draft', 'proposed', 'approved', 'active', 'completed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE slot_status AS ENUM ('open', 'filled', 'confirmed', 'published', 'skipped');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE score_scale AS ENUM ('pct_0_100', 'float_0_1');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =============================================================================
-- 1. format_registry — the canonical list of formats (SPEC: 11)
-- =============================================================================
CREATE TABLE IF NOT EXISTS format_registry (
  format            format_code PRIMARY KEY,
  in_spec           boolean     NOT NULL,          -- one of the 11 SPEC formats
  v0_enabled        boolean     NOT NULL DEFAULT false, -- Repurposer may produce it now
  legacy_alias_of   format_code,                   -- v0 placeholder -> SPEC format
  media             media_kind  NOT NULL,
  payload_required  text[]      NOT NULL DEFAULT '{}', -- top-level keys of content_library.payload
  default_channels  channel_code[] NOT NULL DEFAULT '{}',
  notes             text,
  CHECK (NOT (in_spec AND legacy_alias_of IS NOT NULL)),
  CHECK (NOT v0_enabled OR in_spec)
);

INSERT INTO format_registry (format, in_spec, v0_enabled, legacy_alias_of, media, payload_required, default_channels, notes) VALUES
 ('text_post',         true,  true,  NULL, 'text',        '{}',                                   '{linkedin,facebook}',  'v0 format #1. Body lives in content_library.body.'),
 ('carousel',          true,  true,  NULL, 'image',       '{}',                                   '{linkedin,instagram}', 'v0 format #2. Slides live in content_library.slides.'),
 ('x_thread',          true,  false, NULL, 'text',        '{posts}',                              '{x}',                  'SPEC format.'),
 ('broll',             true,  false, NULL, 'video',       '{clips,total_duration_s}',             '{instagram,linkedin}', 'SPEC format. B-roll clips + on-screen text / voiceover.'),
 ('reel',              true,  false, NULL, 'video',       '{duration_s,beats}',                   '{instagram,facebook}', 'SPEC format.'),
 ('short',             true,  false, NULL, 'video',       '{duration_s,beats,title}',             '{youtube}',            'SPEC format (YouTube Shorts).'),
 ('infographic',       true,  false, NULL, 'image',       '{title,panels,alt_text}',              '{linkedin,instagram}', 'SPEC format.'),
 ('poll',              true,  false, NULL, 'interactive', '{question,options,duration_days}',     '{linkedin,x}',         'SPEC format.'),
 ('interactive_story', true,  false, NULL, 'interactive', '{frames}',                             '{instagram,facebook}', 'SPEC format.'),
 ('email',             true,  false, NULL, 'email',       '{subject,preheader,body_markdown}',    '{email}',              'SPEC format. Sending needs a list + consent; not built.'),
 ('avatar',            true,  false, NULL, 'video',       '{script,duration_s,avatar_profile_ref,consent_ref,ai_disclosure}', '{linkedin,instagram,youtube}', 'SPEC format. Requires Itay''s recorded consent + AI disclosure.'),
 ('thread',             false, false, 'x_thread', 'text',  '{}', '{x}',         'v0 placeholder. Use x_thread.'),
 ('short_video_script', false, false, 'reel',     'video', '{}', '{instagram}', 'v0 placeholder. Use reel / short.'),
 ('article',            false, false, NULL,       'text',  '{}', '{website}',   'v0 placeholder, not in the SPEC format list. Kept for itayfoyerstein.com; no generation.')
ON CONFLICT (format) DO NOTHING;

-- Payload rule mirrored from format_registry.payload_required (CHECKs can't read tables).
-- Keep the two in sync; contracts.md has the full JSON Schemas.
CREATE OR REPLACE FUNCTION payload_ok(f format_code, p jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE f::text
    WHEN 'x_thread'          THEN p ?& ARRAY['posts']             AND jsonb_typeof(p->'posts')  = 'array'
    WHEN 'broll'             THEN p ?& ARRAY['clips','total_duration_s'] AND jsonb_typeof(p->'clips') = 'array'
    WHEN 'reel'              THEN p ?& ARRAY['duration_s','beats'] AND jsonb_typeof(p->'beats') = 'array'
    WHEN 'short'             THEN p ?& ARRAY['duration_s','beats','title'] AND jsonb_typeof(p->'beats') = 'array'
    WHEN 'infographic'       THEN p ?& ARRAY['title','panels','alt_text'] AND jsonb_typeof(p->'panels') = 'array'
    WHEN 'poll'              THEN p ?& ARRAY['question','options','duration_days']
                                  AND jsonb_typeof(p->'options') = 'array'
                                  AND jsonb_array_length(p->'options') BETWEEN 2 AND 4
    WHEN 'interactive_story' THEN p ?& ARRAY['frames']            AND jsonb_typeof(p->'frames') = 'array'
    WHEN 'email'             THEN p ?& ARRAY['subject','preheader','body_markdown']
    WHEN 'avatar'            THEN p ?& ARRAY['script','duration_s','avatar_profile_ref','consent_ref','ai_disclosure']
                                  AND (p->>'ai_disclosure') IS NOT NULL AND length(p->>'ai_disclosure') > 0
    ELSE true    -- text_post, carousel and legacy formats: payload optional
  END
$$;

-- =============================================================================
-- 2. format_specs — extra rule columns for video / interactive / email formats
-- =============================================================================
ALTER TABLE format_specs
  ADD COLUMN IF NOT EXISTS min_duration_s   smallint CHECK (min_duration_s >= 0),
  ADD COLUMN IF NOT EXISTS max_duration_s   smallint CHECK (max_duration_s > 0),
  ADD COLUMN IF NOT EXISTS aspect_ratio     text CHECK (aspect_ratio ~ '^[0-9]+:[0-9]+$'),
  ADD COLUMN IF NOT EXISTS min_items        smallint CHECK (min_items >= 0),  -- thread posts, panels, options, frames, clips
  ADD COLUMN IF NOT EXISTS max_items        smallint CHECK (max_items > 0),
  ADD COLUMN IF NOT EXISTS item_max_chars   integer  CHECK (item_max_chars > 0),
  ADD COLUMN IF NOT EXISTS requires_media   boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS limits_verified  boolean NOT NULL DEFAULT false,   -- platform limits re-checked against the platform's docs
  ADD COLUMN IF NOT EXISTS is_stub          boolean NOT NULL DEFAULT false,   -- structure only, not ready for generation
  ADD COLUMN IF NOT EXISTS notes            text;
DO $$ BEGIN
  ALTER TABLE format_specs ADD CONSTRAINT format_specs_duration_order
    CHECK (min_duration_s IS NULL OR max_duration_s IS NULL OR min_duration_s <= max_duration_s);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE format_specs ADD CONSTRAINT format_specs_items_order
    CHECK (min_items IS NULL OR max_items IS NULL OR min_items <= max_items);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
-- A stub spec may never be the active recipe.
DO $$ BEGIN
  ALTER TABLE format_specs ADD CONSTRAINT format_specs_stub_inactive
    CHECK (NOT (is_stub AND is_active));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =============================================================================
-- 3. prompt_versions — every agent prompt is versioned and human-approved
-- =============================================================================
CREATE TABLE IF NOT EXISTS prompt_versions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent         text NOT NULL CHECK (agent IN ('orchestrator','research','core_creator','repurposer',
                                               'guardian','package_builder','scheduler','distributor','measurement')),
  prompt_key    text NOT NULL CHECK (prompt_key ~ '^[a-z0-9_.]+$'),   -- e.g. 'repurposer.reel.he'
  version       integer NOT NULL CHECK (version > 0),
  format        format_code,                    -- NULL = format-agnostic
  language      lang_code,
  body          text NOT NULL,
  params        jsonb NOT NULL DEFAULT '{}'::jsonb,   -- temperature, max tokens, tool list...
  checksum      text GENERATED ALWAYS AS (md5(body)) STORED,
  status        memory_status NOT NULL DEFAULT 'draft',
  is_active     boolean NOT NULL DEFAULT false,
  parent_id     uuid REFERENCES prompt_versions(id) ON DELETE SET NULL,
  change_note   text,
  correction_ids uuid[] NOT NULL DEFAULT '{}',  -- correction_log rows that motivated this version
  created_by    actor_type NOT NULL DEFAULT 'human',
  approved_by   text,
  approved_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (prompt_key, version),
  CHECK (jsonb_typeof(params) = 'object'),
  CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CHECK (NOT is_active OR status = 'approved')        -- only an approved prompt can run
);
CREATE UNIQUE INDEX IF NOT EXISTS prompt_versions_one_active ON prompt_versions (prompt_key) WHERE is_active;

-- Prompt bodies are immutable once written: edit = new version.
CREATE OR REPLACE FUNCTION prompt_versions_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.body IS DISTINCT FROM OLD.body OR NEW.params IS DISTINCT FROM OLD.params
     OR NEW.prompt_key IS DISTINCT FROM OLD.prompt_key OR NEW.version IS DISTINCT FROM OLD.version THEN
    RAISE EXCEPTION 'prompt_versions % is immutable; insert a new version', OLD.id;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS prompt_versions_no_edit ON prompt_versions;
CREATE TRIGGER prompt_versions_no_edit BEFORE UPDATE ON prompt_versions
  FOR EACH ROW EXECUTE FUNCTION prompt_versions_immutable();

ALTER TABLE core_assets
  ADD COLUMN IF NOT EXISTS prompt_version_id uuid REFERENCES prompt_versions(id) ON DELETE RESTRICT;

-- =============================================================================
-- 4. Guardian thresholds — 0-100 and 0-1 float, side by side
-- =============================================================================
CREATE TABLE IF NOT EXISTS guardian_thresholds (
  profile           text PRIMARY KEY CHECK (profile ~ '^[a-z0-9_]+$'),
  brand_min         smallint NOT NULL CHECK (brand_min BETWEEN 0 AND 100),   -- canonical, 0-100
  icp_min           smallint NOT NULL CHECK (icp_min   BETWEEN 0 AND 100),
  brand_min_float   numeric(4,3) GENERATED ALWAYS AS (brand_min / 100.0) STORED,
  icp_min_float     numeric(4,3) GENERATED ALWAYS AS (icp_min   / 100.0) STORED,
  reject_brand_below smallint NOT NULL DEFAULT 50,
  reject_icp_below   smallint NOT NULL DEFAULT 40,
  brand_cap_when_blocked smallint NOT NULL DEFAULT 74,
  is_active         boolean NOT NULL DEFAULT false,
  source            text NOT NULL,
  needs_review      boolean NOT NULL DEFAULT true,
  approved_by       text,
  approved_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  CHECK (brand_cap_when_blocked < brand_min),
  CHECK (NOT is_active OR approved_by IS NOT NULL OR profile = 'v0')
);
CREATE UNIQUE INDEX IF NOT EXISTS guardian_thresholds_one_active ON guardian_thresholds (is_active) WHERE is_active;

INSERT INTO guardian_thresholds (profile, brand_min, icp_min, brand_cap_when_blocked, is_active, source, needs_review) VALUES
 ('v0',      75, 70, 74, true,  'contracts.md / guardian_checklist.json v1 (current gate)', false),
 ('spec_v1', 85, 85, 84, false, 'SPEC v1.0 threshold 0.85 on the 0-1 scale. Applying it to the ICP score too is an assumption: confirm with Itay', true)
ON CONFLICT (profile) DO NOTHING;

-- 0-1 helpers. Integers stay the stored truth; floats are derived, never stored separately.
CREATE OR REPLACE FUNCTION score_to_pct(v numeric, s score_scale) RETURNS smallint
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT CASE s
    WHEN 'pct_0_100' THEN CASE WHEN v BETWEEN 0 AND 100 THEN round(v)::smallint END
    WHEN 'float_0_1' THEN CASE WHEN v BETWEEN 0 AND 1   THEN round(v * 100)::smallint END
  END
$$;

ALTER TABLE core_assets
  ADD COLUMN IF NOT EXISTS brand_score_float numeric(4,3) GENERATED ALWAYS AS (brand_score / 100.0) STORED,
  ADD COLUMN IF NOT EXISTS icp_relevance_score_float numeric(4,3) GENERATED ALWAYS AS (icp_relevance_score / 100.0) STORED,
  ADD COLUMN IF NOT EXISTS guardian_threshold_profile text REFERENCES guardian_thresholds(profile);

-- =============================================================================
-- 5. 14-day rotation
-- =============================================================================
CREATE TABLE IF NOT EXISTS rotation_plans (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name             text NOT NULL,
  start_date       date NOT NULL,
  days             smallint NOT NULL DEFAULT 14 CHECK (days BETWEEN 1 AND 14),
  end_date         date GENERATED ALWAYS AS (start_date + (days - 1)) STORED,
  timezone         text NOT NULL DEFAULT 'Asia/Jerusalem',
  -- per channel per day caps, e.g. {"linkedin":1,"x":3}. Scheduler never exceeds them.
  daily_caps       jsonb NOT NULL DEFAULT '{"linkedin":1}'::jsonb,
  -- spacing rules, e.g. {"same_core_same_channel_days":4,"min_gap_minutes_same_channel":180}
  constraints      jsonb NOT NULL DEFAULT '{}'::jsonb,
  status           rotation_status NOT NULL DEFAULT 'draft',
  previous_plan_id uuid REFERENCES rotation_plans(id) ON DELETE SET NULL,
  created_by       actor_type NOT NULL DEFAULT 'agent',
  approved_by      text,
  approved_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(daily_caps) = 'object'),
  CHECK (jsonb_typeof(constraints) = 'object'),
  CHECK (status NOT IN ('approved','active','completed') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS rotation_plans_dates ON rotation_plans (start_date);
DROP TRIGGER IF EXISTS rotation_plans_updated ON rotation_plans;
CREATE TRIGGER rotation_plans_updated BEFORE UPDATE ON rotation_plans
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS rotation_slots (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rotation_plan_id uuid NOT NULL REFERENCES rotation_plans(id) ON DELETE CASCADE,
  day              smallint NOT NULL CHECK (day BETWEEN 1 AND 14),
  slot_index       smallint NOT NULL DEFAULT 1 CHECK (slot_index BETWEEN 1 AND 50),
  channel          channel_code NOT NULL,
  format           format_code,                  -- NULL = any approved format
  language         lang_code,                    -- NULL = any
  local_time       time,                         -- in plan timezone; NULL = Scheduler picks
  content_id       uuid REFERENCES content_library(id) ON DELETE SET NULL,
  status           slot_status NOT NULL DEFAULT 'open',
  rationale        text,
  confirmed_by     text,                         -- human who confirmed this slot
  confirmed_at     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (rotation_plan_id, day, channel, slot_index),
  CHECK (status = 'open' OR status = 'skipped' OR content_id IS NOT NULL),
  CHECK (status NOT IN ('confirmed','published') OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS rotation_slots_content ON rotation_slots (content_id);
CREATE UNIQUE INDEX IF NOT EXISTS rotation_slots_one_piece_per_plan
  ON rotation_slots (rotation_plan_id, content_id) WHERE content_id IS NOT NULL;
DROP TRIGGER IF EXISTS rotation_slots_updated ON rotation_slots;
CREATE TRIGGER rotation_slots_updated BEFORE UPDATE ON rotation_slots
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- content_library: new-format payload, rotation links, evergreen recycling, prompt lineage, score floats.
-- Existing rotation_slot (1..14) is kept and means "day in the rotation".
ALTER TABLE content_library
  ADD COLUMN IF NOT EXISTS payload            jsonb,
  ADD COLUMN IF NOT EXISTS media_refs         jsonb,           -- [{kind, path|url, alt_text, license_note}]
  ADD COLUMN IF NOT EXISTS rotation_plan_id   uuid REFERENCES rotation_plans(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rotation_slot_id   uuid REFERENCES rotation_slots(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_evergreen       boolean NOT NULL DEFAULT false,  -- human flag: may be recycled
  ADD COLUMN IF NOT EXISTS recycle_after_days smallint CHECK (recycle_after_days >= 14),
  ADD COLUMN IF NOT EXISTS recycled_from_id   uuid REFERENCES content_library(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS times_published    smallint NOT NULL DEFAULT 0 CHECK (times_published >= 0),
  ADD COLUMN IF NOT EXISTS last_published_at  timestamptz,
  ADD COLUMN IF NOT EXISTS prompt_version_id  uuid REFERENCES prompt_versions(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS guardian_threshold_profile text REFERENCES guardian_thresholds(profile),
  ADD COLUMN IF NOT EXISTS brand_score_float  numeric(4,3) GENERATED ALWAYS AS (brand_score / 100.0) STORED,
  ADD COLUMN IF NOT EXISTS icp_relevance_score_float numeric(4,3) GENERATED ALWAYS AS (icp_relevance_score / 100.0) STORED;

DO $$ BEGIN
  ALTER TABLE content_library ADD CONSTRAINT content_library_payload_shape
    CHECK (payload IS NULL OR jsonb_typeof(payload) = 'object');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE content_library ADD CONSTRAINT content_library_payload_required
    CHECK (format IN ('text_post','carousel','thread','short_video_script','article')
           OR (payload IS NOT NULL AND payload_ok(format, payload)));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE content_library ADD CONSTRAINT content_library_media_refs_shape
    CHECK (media_refs IS NULL OR jsonb_typeof(media_refs) = 'array');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE content_library ADD CONSTRAINT content_library_rotation_day
    CHECK (rotation_plan_id IS NULL OR rotation_slot IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE content_library ADD CONSTRAINT content_library_recycle_not_self
    CHECK (recycled_from_id IS NULL OR recycled_from_id <> id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE INDEX IF NOT EXISTS content_library_rotation ON content_library (rotation_plan_id, rotation_slot);
CREATE INDEX IF NOT EXISTS content_library_evergreen ON content_library (channel, last_published_at)
  WHERE is_evergreen AND status = 'published';

-- =============================================================================
-- 6. performance_logs — per-format metrics + measurement windows
-- =============================================================================
ALTER TABLE performance_logs
  ADD COLUMN IF NOT EXISTS window_label     text CHECK (window_label IN ('24h','72h','7d','14d','28d','lifetime')),
  ADD COLUMN IF NOT EXISTS rotation_plan_id uuid REFERENCES rotation_plans(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS views            integer CHECK (views >= 0),            -- video / story
  ADD COLUMN IF NOT EXISTS avg_watch_s      numeric(7,2) CHECK (avg_watch_s >= 0),
  ADD COLUMN IF NOT EXISTS completion_rate  numeric(5,4) CHECK (completion_rate BETWEEN 0 AND 1),
  ADD COLUMN IF NOT EXISTS poll_votes       integer CHECK (poll_votes >= 0),
  ADD COLUMN IF NOT EXISTS story_interactions integer CHECK (story_interactions >= 0), -- sticker taps / replies
  ADD COLUMN IF NOT EXISTS email_sent       integer CHECK (email_sent >= 0),
  ADD COLUMN IF NOT EXISTS email_opens      integer CHECK (email_opens >= 0),
  ADD COLUMN IF NOT EXISTS email_clicks     integer CHECK (email_clicks >= 0),
  ADD COLUMN IF NOT EXISTS unsubscribes     integer CHECK (unsubscribes >= 0),
  ADD COLUMN IF NOT EXISTS replies          integer CHECK (replies >= 0),
  ADD COLUMN IF NOT EXISTS icp_reach_share  numeric(5,4) CHECK (icp_reach_share BETWEEN 0 AND 1), -- aggregate only, no viewer identities
  ADD COLUMN IF NOT EXISTS confirmed_by     text;  -- human who confirmed icp_conversations / time_saved_minutes

-- Weekly / per-rotation review: what Measurement proposes, what Itay accepted.
CREATE TABLE IF NOT EXISTS measurement_reviews (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rotation_plan_id uuid REFERENCES rotation_plans(id) ON DELETE SET NULL,
  period_start     date NOT NULL,
  period_end       date NOT NULL,
  summary          jsonb NOT NULL DEFAULT '{}'::jsonb,   -- per format/channel/topic aggregates
  proposals        jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{target, change, evidence, status}]
  status           memory_status NOT NULL DEFAULT 'draft',
  approved_by      text,
  approved_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (period_start <= period_end),
  CHECK (jsonb_typeof(proposals) = 'array'),
  CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);

-- =============================================================================
-- 7. audit_log — append-only record of every gate-relevant change
-- =============================================================================
CREATE TABLE IF NOT EXISTS audit_log (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at      timestamptz NOT NULL DEFAULT now(),
  actor_type       actor_type NOT NULL,
  actor_name       text,                       -- 'Itay' / agent name
  action           text NOT NULL CHECK (action IN
                     ('insert','update','delete','status_change','approve','schedule','publish',
                      'guardian_check','prompt_activate','threshold_change','rotation_confirm','other')),
  table_name       text NOT NULL,
  row_id           uuid,
  old_status       text,
  new_status       text,
  changes          jsonb,                      -- {column: [old, new]} for watched columns
  prompt_version_id uuid,
  run_id           text,                       -- e.g. 'runs/001-human-gates'
  note             text
);
CREATE INDEX IF NOT EXISTS audit_log_row ON audit_log (table_name, row_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS audit_log_time ON audit_log (occurred_at DESC);

CREATE OR REPLACE FUNCTION audit_log_append_only() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only';
END $$;
DROP TRIGGER IF EXISTS audit_log_no_update ON audit_log;
CREATE TRIGGER audit_log_no_update BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION audit_log_append_only();

-- Session context set by the app/agent runner:
--   SET LOCAL cmk.actor_type = 'agent'; SET LOCAL cmk.actor_name = 'Repurposer';
--   SET LOCAL cmk.run_id = 'runs/002-...';
-- Missing context defaults to actor_type 'agent' (the safer assumption for a gate log).
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
  FOREACH k IN ARRAY ARRAY['status','approved_by','approved_at','scheduled_at','published_at',
                           'brand_score','icp_relevance_score','is_active','external_url','body','payload']
  LOOP
    IF (v_old -> k) IS DISTINCT FROM (v_new -> k) AND (v_old ? k OR v_new ? k) THEN
      v_changes := v_changes || jsonb_build_object(k, jsonb_build_array(v_old -> k, v_new -> k));
    END IF;
  END LOOP;

  IF TG_OP = 'UPDATE' AND v_changes = '{}'::jsonb THEN
    RETURN NEW;            -- nothing gate-relevant changed
  END IF;

  v_action := CASE
    WHEN TG_OP = 'INSERT' THEN 'insert'
    WHEN TG_OP = 'DELETE' THEN 'delete'
    WHEN v_new->>'status' = 'approved'  AND v_old->>'status' IS DISTINCT FROM 'approved'  THEN 'approve'
    WHEN v_new->>'status' = 'scheduled' AND v_old->>'status' IS DISTINCT FROM 'scheduled' THEN 'schedule'
    WHEN v_new->>'status' = 'published' AND v_old->>'status' IS DISTINCT FROM 'published' THEN 'publish'
    WHEN (v_old->>'status') IS DISTINCT FROM (v_new->>'status') THEN 'status_change'
    WHEN v_changes ? 'brand_score' OR v_changes ? 'icp_relevance_score' THEN 'guardian_check'
    WHEN TG_TABLE_NAME = 'prompt_versions' AND v_changes ? 'is_active' THEN 'prompt_activate'
    WHEN TG_TABLE_NAME = 'guardian_thresholds' THEN 'threshold_change'
    ELSE 'update'
  END;

  INSERT INTO audit_log (actor_type, actor_name, action, table_name, row_id,
                         old_status, new_status, changes, prompt_version_id, run_id)
  VALUES (v_actor, v_name, v_action, TG_TABLE_NAME,
          (coalesce(v_new->>'id', v_old->>'id'))::uuid,
          v_old->>'status', v_new->>'status',
          CASE WHEN TG_OP = 'UPDATE' THEN v_changes END,
          (coalesce(v_new->>'prompt_version_id', v_old->>'prompt_version_id'))::uuid,
          v_run);
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;

-- guardian_thresholds has a text PK, so it gets its own small audit trigger.
CREATE OR REPLACE FUNCTION audit_threshold_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO audit_log (actor_type, actor_name, action, table_name, changes, note)
  VALUES (coalesce(nullif(current_setting('cmk.actor_type', true), ''), 'agent')::actor_type,
          nullif(current_setting('cmk.actor_name', true), ''),
          'threshold_change', 'guardian_thresholds',
          jsonb_build_object('old', CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
                             'new', CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END),
          coalesce(NEW.profile, OLD.profile));
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['content_library','core_assets','approved_facts','core_insights',
                           'brand_voice','format_specs','prompt_versions','rotation_plans','rotation_slots']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_audit', t);
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION audit_status_change()', t || '_audit', t);
  END LOOP;
END $$;
DROP TRIGGER IF EXISTS guardian_thresholds_audit ON guardian_thresholds;
CREATE TRIGGER guardian_thresholds_audit AFTER UPDATE OR DELETE ON guardian_thresholds
  FOR EACH ROW EXECUTE FUNCTION audit_threshold_change();

-- =============================================================================
-- 8. Gate: a new SPEC format can't pass approval while its registry row is off
-- =============================================================================
CREATE OR REPLACE FUNCTION enforce_format_enabled() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE r format_registry%ROWTYPE;
BEGIN
  SELECT * INTO r FROM format_registry WHERE format = NEW.format;
  IF NEW.status IN ('approved','scheduled','published')
     AND (r.format IS NULL OR NOT r.v0_enabled) THEN
    RAISE EXCEPTION 'format % is not enabled in format_registry (v0_enabled=false); a human must enable it first', NEW.format;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS content_library_format_enabled ON content_library;
CREATE TRIGGER content_library_format_enabled BEFORE INSERT OR UPDATE OF status, format ON content_library
  FOR EACH ROW EXECUTE FUNCTION enforce_format_enabled();

COMMIT;
