---
id: J-20261104-027
ts: 2026-11-04T14:41:10+02:00
agent: Codex
workflow: ops
action: implement-focused-cmk-runtime-agents
inputs: [phase-0-3-llm-runtime, user-approved-focused-research-requirements]
outputs: [research/coordinator.mjs, research/runtime.mjs, research/sources.mjs, migrations/015_focused_research.sql, migrations/016_research_evidence.sql, migrations/017_research_agent_tasks.sql, docs/RESEARCH_RUNTIME.md]
status: done
human_gate: none
---

Implemented multiple agents inside CMK: topics, hooks and synthesis with separate draft prompts,
durable role tasks and shared LLM budget. They feed the existing insight/Core/derivative human gates.
Focused The Push management/bottleneck/AI Code Factory profile remains draft/inactive. Source collection
is bounded code with optional Brave search, independent access/payment/budget gates and durable request
reservations. Offline import/plan needs no search calls. Sources retain provenance, unknown metrics and
coverage limits; snippets cannot establish original openings or successful hooks. Reports validate source
references and full-post openings. EditorialGuardian remains heuristic and needs human review.
No real prompt/profile/fact/content approval, paid call, publishing, merge or hosted DB change occurred.
