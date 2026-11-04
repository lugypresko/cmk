BEGIN;
SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='Codex'; SET LOCAL cmk.run_id='phase-C';
SET LOCAL search_path=cmk,public;
ALTER TABLE work_items ADD COLUMN context jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE TABLE work_events (
 id bigserial PRIMARY KEY, work_item_id uuid NOT NULL REFERENCES work_items(id),
 from_state work_state, to_state work_state NOT NULL, from_step text, to_step text NOT NULL,
 actor_type actor_type NOT NULL, actor_name text NOT NULL, run_id text NOT NULL,
 context jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION record_work_event() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO work_events(work_item_id,from_state,to_state,from_step,to_step,actor_type,actor_name,run_id,context)
 VALUES(NEW.id,CASE WHEN TG_OP='UPDATE' THEN OLD.state END,NEW.state,
 CASE WHEN TG_OP='UPDATE' THEN OLD.step END,NEW.step,
 current_setting('cmk.actor_type')::actor_type,current_setting('cmk.actor_name'),current_setting('cmk.run_id'),NEW.context);
 RETURN NEW;
END $$;
CREATE TRIGGER work_items_events AFTER INSERT OR UPDATE ON work_items FOR EACH ROW EXECUTE FUNCTION record_work_event();
CREATE TRIGGER work_events_append_only BEFORE UPDATE OR DELETE ON work_events FOR EACH ROW EXECUTE FUNCTION agent_journal_no_mutate();
-- Draft prompt proposals only. No runtime may activate these as an agent.
INSERT INTO prompt_versions(agent,prompt_key,version,body,created_by,change_note) VALUES
 ('core_creator','core_creator.v0',1,'Read active Business Memory, approved public facts and approved insight. Produce a bilingual CoreAsset under contracts.md. Evidence before diagnosis. One reversible move and an observable change. Never invent client names, prices, testimonials, numbers or consent. Output draft only; human reviews.', 'agent','Phase C draft; human review required'),
 ('repurposer','repurposer.v0',1,'From an approved CoreAsset produce one LinkedIn text_post or carousel HE/EN under contracts.md. Preserve claim strength and fact_ids. New revision for changes. One specific closing question. No invented scenes, prices, client names or numbers. Output draft only.', 'agent','Phase C draft; human review required'),
 ('guardian','editorial_guardian.v0',1,'Score brand and ICP using active brand_voice, icp_profiles and Guardian rubric. Assess source support and derivative value. Explain findings. Editorial scores are advisory and must never override SpecGate or FactGate. No approval or publication.', 'agent','Phase C draft; human review required');
COMMIT;
