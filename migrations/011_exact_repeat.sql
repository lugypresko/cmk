-- =============================================================================
-- CMK migration 011 — exact 14-day repeat (D12 override, 2026-11-03 20:35 Asia/Jerusalem)
-- Additive only. Does not edit migrations 002–010.
--
-- Itay approves one exact version (content hash + asset checksums) and sets both
-- an end date and a repeat count. The scheduler may propose that same
-- content_id/revision every repeat_every_days (default 14) until either limit.
-- Each appearance is its own publish_instance (D3 idempotency unchanged).
--
-- D2 stays audit-only: this migration does NOT revoke approval and does NOT
-- raise when the body changes. A drifted hash or an unusable fact makes the
-- scheduler refuse the repeat; the approval row remains.
-- LinkedIn text_post and carousel only. No other format becomes repeatable.
-- =============================================================================

BEGIN;
SET LOCAL cmk.actor_type='agent';
SET LOCAL cmk.actor_name='migration-011';
SET LOCAL cmk.run_id='exact-repeat';
SET LOCAL search_path=cmk, public;

ALTER TABLE content_library
  ADD COLUMN IF NOT EXISTS is_exact_repeatable boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS repeat_every_days smallint NOT NULL DEFAULT 14,
  ADD COLUMN IF NOT EXISTS repeat_until date,
  ADD COLUMN IF NOT EXISTS max_repeats smallint,
  ADD COLUMN IF NOT EXISTS repeats_done smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS repeat_approved_content_hash text,
  ADD COLUMN IF NOT EXISTS repeat_asset_hashes jsonb;

COMMENT ON COLUMN content_library.is_exact_repeatable IS
  'Human-set. When true, the scheduler may propose this exact revision again. Not a new revision.';
COMMENT ON COLUMN content_library.repeat_every_days IS
  'Days between exact appearances. Default 14. Never below 14.';
COMMENT ON COLUMN content_library.repeat_until IS
  'Last calendar date (Asia/Jerusalem plan dates) on which an exact repeat may be placed. Required when repeatable.';
COMMENT ON COLUMN content_library.max_repeats IS
  'How many additional appearances are allowed after the original. Required when repeatable. Stops with repeat_until, whichever comes first.';
COMMENT ON COLUMN content_library.repeats_done IS
  'Exact appearances published after the original. Incremented when a later publish_instance is confirmed. Does not by itself revoke anything.';
COMMENT ON COLUMN content_library.repeat_approved_content_hash IS
  'content_hash() of the version Itay approved for verbatim repeat. Compared at propose/confirm/send. A mismatch refuses the repeat (D2: approval stays).';
COMMENT ON COLUMN content_library.repeat_asset_hashes IS
  'JSON array of sha256 checksums for the approved assets (empty array when the piece has none).';

CREATE OR REPLACE FUNCTION repeat_asset_hashes_ok(j jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT j IS NOT NULL AND jsonb_typeof(j) = 'array' AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements_text(j) AS hash(value) WHERE value !~ '^[0-9a-f]{64}$'
  )
$$;

DO $$ BEGIN
  ALTER TABLE content_library ADD CONSTRAINT content_library_repeat_every_days
    CHECK (repeat_every_days >= 14);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE content_library ADD CONSTRAINT content_library_repeats_done_nonneg
    CHECK (repeats_done >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE content_library ADD CONSTRAINT content_library_max_repeats_positive
    CHECK (max_repeats IS NULL OR max_repeats >= 1);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE content_library ADD CONSTRAINT content_library_exact_repeat_shape
    CHECK (
      NOT is_exact_repeatable OR (
        channel = 'linkedin'
        AND format IN ('text_post', 'carousel')
        AND status IN ('approved', 'scheduled', 'published')
        AND repeat_every_days >= 14
        AND repeat_until IS NOT NULL
        AND max_repeats IS NOT NULL
        AND repeats_done BETWEEN 0 AND max_repeats
        AND repeat_approved_content_hash ~ '^[0-9a-f]{64}$'
        AND repeat_asset_hashes_ok(repeat_asset_hashes)
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Granting or editing the rule is human-only. The default cadence on ordinary
-- inserts is not a grant. Agents may still edit body text (D2); they cannot
-- turn that edit into a repeat authorization.
CREATE OR REPLACE FUNCTION exact_repeat_human_only() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(nullif(current_setting('cmk.actor_type', true), ''), 'agent') <> 'human' THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.is_exact_repeatable OR NEW.repeat_until IS NOT NULL OR NEW.max_repeats IS NOT NULL
         OR NEW.repeats_done <> 0 OR NEW.repeat_approved_content_hash IS NOT NULL
         OR NEW.repeat_asset_hashes IS NOT NULL THEN
        RAISE EXCEPTION 'exact repeat rule is human-only';
      END IF;
    ELSIF NEW.is_exact_repeatable IS DISTINCT FROM OLD.is_exact_repeatable
       OR NEW.repeat_every_days IS DISTINCT FROM OLD.repeat_every_days
       OR NEW.repeat_until IS DISTINCT FROM OLD.repeat_until
       OR NEW.max_repeats IS DISTINCT FROM OLD.max_repeats
       OR NEW.repeats_done IS DISTINCT FROM OLD.repeats_done
       OR NEW.repeat_approved_content_hash IS DISTINCT FROM OLD.repeat_approved_content_hash
       OR NEW.repeat_asset_hashes IS DISTINCT FROM OLD.repeat_asset_hashes THEN
      RAISE EXCEPTION 'exact repeat rule is human-only';
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS content_library_exact_repeat_human ON content_library;
CREATE TRIGGER content_library_exact_repeat_human
  BEFORE INSERT OR UPDATE ON content_library
  FOR EACH ROW EXECUTE FUNCTION exact_repeat_human_only();

CREATE INDEX IF NOT EXISTS content_library_exact_repeat
  ON content_library (repeat_until, id) WHERE is_exact_repeatable;

COMMIT;
