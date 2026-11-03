-- 004: agent activity journal (agent memory + human log). Append-only.
CREATE SCHEMA IF NOT EXISTS cmk;

CREATE TABLE IF NOT EXISTS cmk.agent_journal (
  id          text PRIMARY KEY CHECK (id ~ '^J-[0-9]{8}-[0-9]{3,}$'),
  ts          timestamptz NOT NULL DEFAULT now(),
  agent       text NOT NULL,
  workflow    text NOT NULL CHECK (workflow IN ('A','B','C','ops')),
  action      text NOT NULL,
  inputs      text[] NOT NULL DEFAULT '{}',
  outputs     text[] NOT NULL DEFAULT '{}',
  status      text NOT NULL CHECK (status IN ('started','done','approved','rejected','blocked','failed')),
  human_gate  text NOT NULL DEFAULT 'none',
  notes       text,
  run_id      text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS agent_journal_ts_idx       ON cmk.agent_journal (ts DESC);
CREATE INDEX IF NOT EXISTS agent_journal_agent_ts_idx ON cmk.agent_journal (agent, ts DESC);
CREATE INDEX IF NOT EXISTS agent_journal_wf_ts_idx    ON cmk.agent_journal (workflow, ts DESC);
CREATE INDEX IF NOT EXISTS agent_journal_gate_idx     ON cmk.agent_journal (human_gate) WHERE human_gate NOT IN ('none','itay_approved');
CREATE INDEX IF NOT EXISTS agent_journal_outputs_gin  ON cmk.agent_journal USING gin (outputs);

-- Append-only: block UPDATE/DELETE.
CREATE OR REPLACE FUNCTION cmk.agent_journal_no_mutate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'cmk.agent_journal is append-only'; END $$;
DROP TRIGGER IF EXISTS agent_journal_append_only ON cmk.agent_journal;
CREATE TRIGGER agent_journal_append_only BEFORE UPDATE OR DELETE ON cmk.agent_journal
  FOR EACH ROW EXECUTE FUNCTION cmk.agent_journal_no_mutate();

-- ErrorWatcher uses agent_journal + correction_log; no new tables required in v0.
