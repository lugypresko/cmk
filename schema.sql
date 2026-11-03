-- =============================================================================
-- Content Memory Kitchen (CMK) — Business Memory v0
-- Owner: The Push / Itay Foyerstein  ·  Source of truth: https://itayfoyerstein.com
-- Target: PostgreSQL 14+ (uses gen_random_uuid() from core / pgcrypto)
--
-- Layers:
--   MEMORY    brand_voice, icp_profiles, approved_facts, core_insights,
--             past_content, format_specs, correction_log
--   PIPELINE  core_assets (Core) -> content_library (Multiply) -> performance_logs
--   GUARDIAN  scores + guardian_report on core_assets / content_library;
--             only rows with status 'approved' may be scheduled/published.
--
-- Rules:
--   * No pricing, no client names unless they exist verbatim in approved_facts
--     with an explicit public source.
--   * Hebrew (he) and English (en) are first-class; HE seed text below is a
--     draft translation and is marked needs_review = true until Itay approves.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid() on PG < 13
CREATE SCHEMA IF NOT EXISTS cmk;
SET search_path = cmk, public;

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
CREATE TYPE lang_code      AS ENUM ('en', 'he');
CREATE TYPE channel_code   AS ENUM ('linkedin', 'instagram', 'facebook', 'x', 'website');
CREATE TYPE format_code    AS ENUM (
  'text_post',          -- v0 format #1 (LinkedIn first)
  'carousel',           -- v0 format #2 (LinkedIn / Instagram)
  'thread',             -- X, later
  'short_video_script', -- IG / FB reels, later
  'article'             -- itayfoyerstein.com, later
);
CREATE TYPE memory_status  AS ENUM ('draft', 'approved', 'retired');
CREATE TYPE content_status AS ENUM (
  'draft', 'in_review', 'needs_changes', 'approved',
  'scheduled', 'published', 'rejected', 'archived'
);
CREATE TYPE actor_type     AS ENUM ('human', 'agent');
CREATE TYPE confidentiality_level AS ENUM ('public', 'anonymized', 'private');

-- -----------------------------------------------------------------------------
-- updated_at helper
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- =============================================================================
-- MEMORY
-- =============================================================================

-- brand_voice: versioned voice + positioning. Exactly one active row.
CREATE TABLE brand_voice (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version          integer NOT NULL CHECK (version > 0),
  is_active        boolean NOT NULL DEFAULT false,
  brand_name       text    NOT NULL,
  promise_en       text    NOT NULL,
  promise_he       text,
  sub_promise_en   text,
  sub_promise_he   text,
  positioning_en   text    NOT NULL,
  positioning_he   text,
  offering_en      text    NOT NULL,
  offering_he      text,
  tone_principles  jsonb   NOT NULL DEFAULT '[]'::jsonb,   -- [{rule, why}]
  say_phrases      text[]  NOT NULL DEFAULT '{}',          -- preferred language
  avoid_phrases    text[]  NOT NULL DEFAULT '{}',          -- banned / off-voice
  cta_primary_en   text,
  cta_primary_he   text,
  source_url       text    NOT NULL,
  needs_review     boolean NOT NULL DEFAULT true,
  approved_by      text,
  approved_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (version),
  CHECK (approved_at IS NULL OR approved_by IS NOT NULL),
  CHECK (jsonb_typeof(tone_principles) = 'array')
);
CREATE UNIQUE INDEX brand_voice_one_active ON brand_voice (is_active) WHERE is_active;
CREATE TRIGGER brand_voice_updated BEFORE UPDATE ON brand_voice
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- icp_profiles: who content is for.
CREATE TABLE icp_profiles (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug             text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9_-]+$'),
  name_en          text NOT NULL,
  name_he          text,
  priority         smallint NOT NULL DEFAULT 1 CHECK (priority BETWEEN 1 AND 5), -- 1 = primary
  roles            text[] NOT NULL CHECK (cardinality(roles) > 0),
  secondary_roles  text[] NOT NULL DEFAULT '{}',
  company_context_en text NOT NULL,
  company_context_he text,
  pains            jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{en, he}]
  strong_fit       jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{en, he}]
  not_a_fit        jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{en, he}]
  languages        lang_code[] NOT NULL DEFAULT '{en,he}',
  channels         channel_code[] NOT NULL DEFAULT '{linkedin}',
  is_active        boolean NOT NULL DEFAULT true,
  needs_review     boolean NOT NULL DEFAULT true,
  source_url       text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(pains) = 'array'),
  CHECK (jsonb_typeof(strong_fit) = 'array'),
  CHECK (jsonb_typeof(not_a_fit) = 'array')
);
CREATE INDEX icp_profiles_active ON icp_profiles (priority) WHERE is_active;
CREATE TRIGGER icp_profiles_updated BEFORE UPDATE ON icp_profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- approved_facts: the ONLY claims content may state as fact (credentials,
-- offering, method, proof). Guardian rejects factual claims not traceable here.
CREATE TABLE approved_facts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fact_key         text NOT NULL UNIQUE CHECK (fact_key ~ '^[a-z0-9_.]+$'),
  category         text NOT NULL CHECK (category IN
                     ('credential','offering','method','proof','boundary','audience')),
  statement_en     text NOT NULL,
  statement_he     text,
  source_url       text,
  source_note      text,
  confidentiality  confidentiality_level NOT NULL DEFAULT 'public',
  status           memory_status NOT NULL DEFAULT 'draft',
  approved_by      text,
  approved_at      timestamptz,
  review_by        timestamptz,                -- re-verify date (e.g. hour counts)
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CHECK (source_url IS NOT NULL OR source_note IS NOT NULL)
);
CREATE INDEX approved_facts_usable ON approved_facts (category)
  WHERE status = 'approved' AND confidentiality = 'public';
CREATE TRIGGER approved_facts_updated BEFORE UPDATE ON approved_facts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- core_insights: raw ideas/patterns/observations (the "ingredients").
CREATE TABLE core_insights (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title            text NOT NULL,
  insight_en       text,
  insight_he       text,
  pattern_name     text,                       -- e.g. 'decision_dependency'
  origin           text NOT NULL CHECK (origin IN
                     ('session_observation','site','voice_note','past_content','conversation','other')),
  confidentiality  confidentiality_level NOT NULL DEFAULT 'anonymized',
  icp_profile_id   uuid REFERENCES icp_profiles(id) ON DELETE SET NULL,
  tags             text[] NOT NULL DEFAULT '{}',
  status           memory_status NOT NULL DEFAULT 'draft',
  approved_by      text,
  approved_at      timestamptz,
  created_by       actor_type NOT NULL DEFAULT 'human',
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (insight_en IS NOT NULL OR insight_he IS NOT NULL),
  CHECK (status <> 'approved' OR approved_at IS NOT NULL)
);
CREATE INDEX core_insights_status ON core_insights (status, created_at DESC);
CREATE INDEX core_insights_icp    ON core_insights (icp_profile_id);
CREATE INDEX core_insights_tags   ON core_insights USING gin (tags);
CREATE TRIGGER core_insights_updated BEFORE UPDATE ON core_insights
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- format_specs: per format x channel x language rules ("recipes").
CREATE TABLE format_specs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  format           format_code  NOT NULL,
  channel          channel_code NOT NULL,
  language         lang_code    NOT NULL,
  version          integer NOT NULL DEFAULT 1 CHECK (version > 0),
  is_active        boolean NOT NULL DEFAULT false,
  min_chars        integer CHECK (min_chars >= 0),
  max_chars        integer CHECK (max_chars > 0),
  max_slides       smallint CHECK (max_slides > 0),          -- carousel only
  structure        jsonb NOT NULL DEFAULT '[]'::jsonb,       -- ordered sections
  rules            jsonb NOT NULL DEFAULT '[]'::jsonb,       -- [{rule, severity}]
  example_ids      uuid[] NOT NULL DEFAULT '{}',             -- past_content exemplars
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (format, channel, language, version),
  CHECK (min_chars IS NULL OR max_chars IS NULL OR min_chars <= max_chars),
  CHECK (max_slides IS NULL OR format = 'carousel')
);
CREATE UNIQUE INDEX format_specs_one_active
  ON format_specs (format, channel, language) WHERE is_active;
CREATE TRIGGER format_specs_updated BEFORE UPDATE ON format_specs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- past_content: historical posts imported from channels (pre-CMK or external).
CREATE TABLE past_content (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel          channel_code NOT NULL,
  format           format_code,
  language         lang_code NOT NULL,
  external_post_id text,
  url              text,
  body             text NOT NULL,
  published_at     timestamptz,
  is_exemplar      boolean NOT NULL DEFAULT false,   -- good voice reference
  is_anti_example  boolean NOT NULL DEFAULT false,   -- what NOT to do
  notes            text,
  tags             text[] NOT NULL DEFAULT '{}',
  imported_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (channel, external_post_id),
  CHECK (NOT (is_exemplar AND is_anti_example))
);
CREATE INDEX past_content_channel_date ON past_content (channel, published_at DESC);
CREATE INDEX past_content_exemplars    ON past_content (channel, language) WHERE is_exemplar;

-- =============================================================================
-- PIPELINE: Core -> Multiply
-- =============================================================================

-- core_assets: one long-form, channel-agnostic "Core" per idea. Source for Multiply.
CREATE TABLE core_assets (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  core_insight_id     uuid REFERENCES core_insights(id) ON DELETE RESTRICT,
  brand_voice_id      uuid NOT NULL REFERENCES brand_voice(id) ON DELETE RESTRICT,
  icp_profile_id      uuid NOT NULL REFERENCES icp_profiles(id) ON DELETE RESTRICT,
  title               text NOT NULL,
  thesis_en           text,                 -- one-sentence point
  thesis_he           text,
  body_en             text,
  body_he             text,
  primary_language    lang_code NOT NULL DEFAULT 'en',
  key_points          jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{en, he}]
  cta_en              text,
  cta_he              text,
  status              content_status NOT NULL DEFAULT 'draft',
  brand_score         smallint CHECK (brand_score BETWEEN 0 AND 100),
  icp_relevance_score smallint CHECK (icp_relevance_score BETWEEN 0 AND 100),
  guardian_report     jsonb,                -- see contracts.md GuardianReport
  guardian_checked_at timestamptz,
  created_by          actor_type NOT NULL DEFAULT 'agent',
  approved_by         text,
  approved_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (body_en IS NOT NULL OR body_he IS NOT NULL),
  CHECK (status IN ('draft','in_review','needs_changes','approved','rejected','archived')),
  CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL
                                  AND brand_score IS NOT NULL AND icp_relevance_score IS NOT NULL))
);
CREATE INDEX core_assets_status ON core_assets (status, created_at DESC);
CREATE INDEX core_assets_icp    ON core_assets (icp_profile_id);
CREATE INDEX core_assets_insight ON core_assets (core_insight_id);
CREATE TRIGGER core_assets_updated BEFORE UPDATE ON core_assets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- content_library: channel-specific pieces derived from a Core ("Multiply").
CREATE TABLE content_library (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  core_asset_id       uuid NOT NULL REFERENCES core_assets(id) ON DELETE RESTRICT,
  format_spec_id      uuid NOT NULL REFERENCES format_specs(id) ON DELETE RESTRICT,
  format              format_code  NOT NULL,
  channel             channel_code NOT NULL,
  language            lang_code    NOT NULL,
  revision            integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  parent_id           uuid REFERENCES content_library(id) ON DELETE SET NULL, -- previous revision
  title               text,
  hook                text,
  body                text NOT NULL,
  slides              jsonb,                -- carousel: [{n, headline, text}]
  cta                 text,
  hashtags            text[] NOT NULL DEFAULT '{}',
  status              content_status NOT NULL DEFAULT 'draft',
  brand_score         smallint CHECK (brand_score BETWEEN 0 AND 100),
  icp_relevance_score smallint CHECK (icp_relevance_score BETWEEN 0 AND 100),
  guardian_report     jsonb,
  guardian_checked_at timestamptz,
  scheduled_at        timestamptz,
  published_at        timestamptz,
  external_post_id    text,
  external_url        text,
  rotation_slot       smallint CHECK (rotation_slot BETWEEN 1 AND 14), -- 14-day rotation (later)
  created_by          actor_type NOT NULL DEFAULT 'agent',
  approved_by         text,
  approved_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (slides IS NULL OR (format = 'carousel' AND jsonb_typeof(slides) = 'array')),
  CHECK (format <> 'carousel' OR slides IS NOT NULL),
  -- Guardian gate: nothing reaches approved/scheduled/published without scores + human approval
  CHECK (status NOT IN ('approved','scheduled','published')
         OR (brand_score IS NOT NULL AND icp_relevance_score IS NOT NULL
             AND approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CHECK (status <> 'scheduled' OR scheduled_at IS NOT NULL),
  CHECK (status <> 'published' OR published_at IS NOT NULL)
);
CREATE UNIQUE INDEX content_library_revision
  ON content_library (core_asset_id, format, channel, language, revision);
CREATE INDEX content_library_status    ON content_library (status, created_at DESC);
CREATE INDEX content_library_schedule  ON content_library (scheduled_at)
  WHERE status = 'scheduled';
CREATE INDEX content_library_channel   ON content_library (channel, published_at DESC);
CREATE UNIQUE INDEX content_library_ext_post
  ON content_library (channel, external_post_id) WHERE external_post_id IS NOT NULL;
CREATE TRIGGER content_library_updated BEFORE UPDATE ON content_library
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Fact traceability: which approved_facts a Core / piece relies on.
CREATE TABLE content_fact_refs (
  approved_fact_id uuid NOT NULL REFERENCES approved_facts(id) ON DELETE RESTRICT,
  core_asset_id    uuid REFERENCES core_assets(id) ON DELETE CASCADE,
  content_id       uuid REFERENCES content_library(id) ON DELETE CASCADE,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (num_nonnulls(core_asset_id, content_id) = 1)
);
CREATE UNIQUE INDEX content_fact_refs_core
  ON content_fact_refs (core_asset_id, approved_fact_id) WHERE core_asset_id IS NOT NULL;
CREATE UNIQUE INDEX content_fact_refs_piece
  ON content_fact_refs (content_id, approved_fact_id) WHERE content_id IS NOT NULL;
CREATE INDEX content_fact_refs_fact ON content_fact_refs (approved_fact_id);

-- =============================================================================
-- FEEDBACK
-- =============================================================================

-- performance_logs: metric snapshots + the two success metrics
-- (time saved, ICP conversations).
CREATE TABLE performance_logs (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id          uuid REFERENCES content_library(id) ON DELETE CASCADE,
  past_content_id     uuid REFERENCES past_content(id) ON DELETE CASCADE,
  captured_at         timestamptz NOT NULL DEFAULT now(),
  impressions         integer CHECK (impressions >= 0),
  reactions           integer CHECK (reactions >= 0),
  comments            integer CHECK (comments >= 0),
  shares              integer CHECK (shares >= 0),
  saves               integer CHECK (saves >= 0),
  clicks              integer CHECK (clicks >= 0),
  profile_visits      integer CHECK (profile_visits >= 0),
  icp_conversations   integer NOT NULL DEFAULT 0 CHECK (icp_conversations >= 0), -- DMs / calls with ICP
  time_saved_minutes  integer CHECK (time_saved_minutes >= 0),  -- vs. manual baseline
  source              text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','api','import')),
  raw                 jsonb,
  notes               text,
  CHECK (num_nonnulls(content_id, past_content_id) = 1)
);
CREATE UNIQUE INDEX performance_logs_content_snap
  ON performance_logs (content_id, captured_at) WHERE content_id IS NOT NULL;
CREATE UNIQUE INDEX performance_logs_past_snap
  ON performance_logs (past_content_id, captured_at) WHERE past_content_id IS NOT NULL;
CREATE INDEX performance_logs_captured ON performance_logs (captured_at DESC);

-- correction_log: every human edit / Guardian rejection reason. Repeated
-- corrections get promoted into brand_voice / format_specs / approved_facts.
CREATE TABLE correction_log (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id          uuid REFERENCES content_library(id) ON DELETE SET NULL,
  core_asset_id       uuid REFERENCES core_assets(id) ON DELETE SET NULL,
  correction_type     text NOT NULL CHECK (correction_type IN
                        ('voice','fact','icp','format','confidentiality','language','cta','other')),
  severity            text NOT NULL DEFAULT 'minor' CHECK (severity IN ('minor','major','blocker')),
  before_text         text,
  after_text          text,
  reason              text NOT NULL,
  rule_candidate      text,                 -- proposed general rule
  promoted_to         text CHECK (promoted_to IN ('brand_voice','format_specs','approved_facts','icp_profiles')),
  promoted_ref_id     uuid,
  promoted_at         timestamptz,
  corrected_by        actor_type NOT NULL DEFAULT 'human',
  corrector_name      text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  CHECK ((promoted_to IS NULL) = (promoted_at IS NULL))
);
CREATE INDEX correction_log_type      ON correction_log (correction_type, created_at DESC);
CREATE INDEX correction_log_unpromoted ON correction_log (created_at DESC)
  WHERE promoted_at IS NULL AND rule_candidate IS NOT NULL;
CREATE INDEX correction_log_content   ON correction_log (content_id);

-- =============================================================================
-- SEED (from https://itayfoyerstein.com, fetched 2026-11-03)
-- English = site copy. Hebrew = DRAFT translation, needs_review = true.
-- =============================================================================

INSERT INTO brand_voice (
  version, is_active, brand_name,
  promise_en, promise_he, sub_promise_en, sub_promise_he,
  positioning_en, positioning_he, offering_en, offering_he,
  tone_principles, say_phrases, avoid_phrases,
  cta_primary_en, cta_primary_he, source_url, needs_review
) VALUES (
  1, true, 'The Push / Itay Foyerstein',
  'Your team can do the work. The decisions still come back to you.',
  'הצוות שלך יודע לעשות את העבודה. ההחלטות עדיין חוזרות אליך.',
  'The goal isn''t to be needed less. It''s to be needed at the right level.',
  'המטרה היא לא שיצטרכו אותך פחות. אלא שיצטרכו אותך ברמה הנכונה.',
  'Technical leadership coaching: 1:1 coaching for Engineering Managers, Group Managers and Directors in growing B2B SaaS companies.',
  'אימון מנהיגות טכנולוגית: ליווי 1:1 למנהלי פיתוח, ראשי קבוצות ודירקטורים בחברות B2B SaaS בצמיחה.',
  'Practical 1:1 work on the decisions, authority, context and relationships in your role. Start with one real situation. 12 weeks, 6 private 1:1 sessions, 1 problem worth changing.',
  'עבודה פרקטית 1:1 על ההחלטות, הסמכות, ההקשר והיחסים בתפקיד שלך. מתחילים ממצב אמיתי אחד. 12 שבועות, 6 מפגשים אישיים, בעיה אחת ששווה לשנות.',
  '[
    {"rule":"Evidence before diagnosis: don''t call it a bottleneck before the evidence earns it.","why":"Site method"},
    {"rule":"Name the working pattern (e.g. decision dependency), not the person''s flaw.","why":"Frames it as a system, not a capability/confidence issue"},
    {"rule":"Ask the useful question: what genuinely needs your judgment vs. what has learned to wait for it.","why":"Core reframe vs. generic ''delegate more''"},
    {"rule":"Concrete, observable change over testimonials and hype.","why":"''Not testimonials. What changed in the work.''"},
    {"rule":"Calm, direct, practitioner voice: real people, real trade-offs, real accountability.","why":"25+ years inside the problems"},
    {"rule":"Propose one reversible leadership move, not a framework.","why":"Method: test, move, read, adjust"},
    {"rule":"Respect confidentiality: anonymize; never imply session content is shared.","why":"Site confidentiality statement"}
  ]'::jsonb,
  ARRAY[
    'needed at the right level',
    'decisions still come back to you',
    'decision dependency',
    'what genuinely needs your judgment',
    'what has simply learned to wait for it',
    'one real situation',
    'a reversible leadership move',
    'the work slows rather than stops',
    'accountability quietly turned into being present'
  ],
  ARRAY[
    'just delegate more',
    'bottleneck (as an unearned label)',
    'hustle / crush it / 10x',
    'guaranteed results',
    'pricing or discount claims',
    'unapproved client or company names',
    'motivational clichés'
  ],
  'Start with one real situation. Bring one current decision, review, escalation or meeting that keeps coming back to you.',
  'מתחילים ממצב אמיתי אחד. הביאו החלטה, סקירה, הסלמה או פגישה אחת שממשיכה לחזור אליכם.',
  'https://itayfoyerstein.com',
  true
);

INSERT INTO icp_profiles (
  slug, name_en, name_he, priority, roles, secondary_roles,
  company_context_en, company_context_he,
  pains, strong_fit, not_a_fit, languages, channels, source_url, needs_review
) VALUES (
  'eng-leader-growing-b2b-saas',
  'Engineering leader in a growing B2B SaaS',
  'מנהל/ת הנדסה בחברת B2B SaaS בצמיחה',
  1,
  ARRAY['Engineering Manager','Group Manager','Director of Engineering / R&D Director'],
  ARRAY['CTO','VP R&D'],   -- secondary: reached via LinkedIn content
  'Growing B2B SaaS company; scope has grown; leads capable people.',
  'חברת B2B SaaS בצמיחה; ההיקף גדל; מוביל/ה אנשים מוכשרים.',
  '[
    {"en":"A decision that should close without me keeps coming back for one last check.","he":"החלטה שאמורה להיסגר בלעדיי חוזרת אליי לבדיקה אחרונה."},
    {"en":"A meeting I somehow still need to attend: accountability turned into being present.","he":"פגישה שאני איכשהו עדיין חייב/ת להיות בה: אחריות הפכה לנוכחות."},
    {"en":"An escalation that keeps climbing back up.","he":"הסלמה שממשיכה לטפס בחזרה למעלה."},
    {"en":"Work that stalls when I am unavailable.","he":"עבודה שנתקעת כשאני לא זמין/ה."},
    {"en":"Strategic work only starts after the meetings end; the calendar is full.","he":"העבודה האסטרטגית מתחילה רק אחרי שהפגישות נגמרות; היומן מלא."}
  ]'::jsonb,
  '[
    {"en":"Scope has grown, but too much still depends on direct involvement.","he":"ההיקף גדל, אבל יותר מדי עדיין תלוי במעורבות ישירה."},
    {"en":"Leads capable people and wants more leverage without becoming disconnected.","he":"מוביל/ה אנשים מוכשרים ורוצה יותר מינוף בלי להתנתק."},
    {"en":"Willing to test changes between sessions.","he":"מוכן/ה לבחון שינויים בין המפגשים."}
  ]'::jsonb,
  '[
    {"en":"Doesn''t have the authority the role requires.","he":"אין את הסמכות שהתפקיד דורש."},
    {"en":"The team is materially understaffed.","he":"הצוות חסר משמעותית בכוח אדם."},
    {"en":"The role or organization design is unresolved.","he":"התפקיד או המבנה הארגוני לא מוגדרים."}
  ]'::jsonb,
  '{en,he}', '{linkedin,website,instagram,facebook,x}',
  'https://itayfoyerstein.com', true
);

-- Minimal approved_facts from public site copy (no pricing, no names).
-- Left as 'draft' so Itay explicitly approves before Guardian treats them as usable.
INSERT INTO approved_facts (fact_key, category, statement_en, statement_he, source_url) VALUES
 ('credential.years',     'credential', '25+ years in technology and delivery.', '25+ שנים בטכנולוגיה ובדליברי.', 'https://itayfoyerstein.com'),
 ('credential.hours',     'credential', '1000+ coaching hours.', '1000+ שעות אימון.', 'https://itayfoyerstein.com'),
 ('offering.structure',   'offering',   '12 weeks, 6 private 1:1 sessions, 1 problem worth changing.', '12 שבועות, 6 מפגשים אישיים 1:1, בעיה אחת ששווה לשנות.', 'https://itayfoyerstein.com'),
 ('offering.first_read',  'offering',   'Bring one current case; you get a written first read before anyone asks for a call.', 'הביאו מקרה נוכחי אחד; תקבלו קריאה ראשונה בכתב לפני שמישהו מבקש שיחה.', 'https://itayfoyerstein.com'),
 ('method.loop',          'method',     'See the real case and the system around it; challenge the first explanation; move one real leadership behavior; read how people respond; adjust what comes next.', 'לראות את המקרה האמיתי ואת המערכת סביבו; לאתגר את ההסבר הראשון; להזיז התנהגות מנהיגותית אחת; לקרוא את התגובות; להתאים את הצעד הבא.', 'https://itayfoyerstein.com'),
 ('boundary.confidentiality','boundary','Names are withheld where confidentiality requires it. Funding by a company never authorizes sharing what is said in sessions.', 'שמות לא נחשפים כשהסודיות מחייבת. מימון על ידי חברה אף פעם לא מתיר שיתוף של מה שנאמר במפגשים.', 'https://itayfoyerstein.com');

COMMIT;
