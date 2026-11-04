-- =============================================================================
-- CMK migration 013 — research.v0 draft prompt
-- The orchestrator's first step calls prompt key 'research.v0', which was
-- never seeded, so every real (non-fixture) run stopped at
-- human_gate:activate_prompt_or_supply_provider before any work existed.
-- This seeds the missing prompt as a DRAFT, exactly like the three Phase C
-- prompts in migration 008. It is not approved and not active: Itay reviews
-- the wording and approves/activates it himself (docs/OPERATIONS.md).
-- No agent executes this prompt. Fixture mode stays the only runnable path
-- until a human approves a prompt and a provider is connected.
-- Applies on top of schema.sql + 002..012. Additive only. Idempotent.
-- =============================================================================
BEGIN;
SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='migration-runner'; SET LOCAL cmk.run_id='local-apply';
SET LOCAL search_path=cmk,public;
INSERT INTO prompt_versions(agent,prompt_key,version,body,created_by,change_note)
SELECT 'research','research.v0',1,
 'From the supplied idea or source notes produce one CoreInsight under contracts.md: a title plus the insight in Hebrew and/or English. Work only from the supplied material, approved public facts and active Business Memory; never invent facts, numbers, sources, client names or quotations. Set confidentiality to public or anonymized; when material names a private client or person, anonymize it. When the idea lacks evidence, state what is missing instead of filling the gap. Output draft only; a human reviews and approves.',
 'agent','Phase C draft; human review required'
WHERE NOT EXISTS (SELECT 1 FROM prompt_versions WHERE prompt_key='research.v0' AND version=1);
COMMIT;
