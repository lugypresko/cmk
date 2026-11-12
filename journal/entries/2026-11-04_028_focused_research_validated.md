---
id: J-20261104-028
ts: 2026-11-04T14:41:51+02:00
agent: Codex
workflow: ops
action: validate-focused-runtime-research-agents
inputs: [scripts/test_all.sh, research/tests, llm/tests/client.test.mjs]
outputs: [docs/VALIDATION.md]
status: done
human_gate: none
---

Fresh apply through017 plus rollback SQL:22/22 passed. All93 tests passed: Guardian19, files8,
fonts7, runtime16, LLM14 and focused research29. Separate topic/hooks/synthesis calls used mocked
transport, distinct prompts and shared budget, persisted their tasks and stopped at insight approval.
Source permission/budget, provenance, unknown metrics, exact observed openings and draft boundaries
were checked. Existing LLM tests pin research v1; new tests cover v2. Persistent DB inspection found
zero model/search requests, active prompts/profiles or approved facts; all six site facts stay draft.
No live coverage, live semantic quality, paid calls or business approvals are claimed.
