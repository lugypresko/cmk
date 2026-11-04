---
id: J-20261104-025
ts: 2026-11-04T12:03:09+02:00
agent: Codex
workflow: ops
action: implement-llm-generation-runtime
inputs: [phase-0-2-readiness, runtime/agents.mjs, runtime/orchestrator.mjs]
outputs: [llm/client.mjs, migrations/014_llm_runtime.sql, docs/LLM_RUNTIME.md]
status: done
human_gate: none
---

Implemented the explicitly authorized next step on phase-0-3-llm-runtime. Reused the existing
Orchestrator and prompt keys. Added configurable transport with default-off payment, full approved
insight/Core + business-memory input, draft output validation, durable budget reservations outside
content transactions and metadata-only audit rows. Core/derivatives share a run budget. Cached
successful responses resume without resending; failed/unknown requests retain conservative charges.
Focused tests passed with injected provider responses only, including first HE text package and
human gates, budgets, concurrency, transport errors, invalid model approvals and unsupported facts.
No real prompt/fact/content approvals or paid API calls were made.
