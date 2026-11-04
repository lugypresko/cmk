---
id: J-20261104-029
ts: 2026-11-04T14:43:12+02:00
agent: Codex
workflow: ops
action: harden-research-after-review
inputs: [research/runtime.mjs, research/tests/runtime.test.mjs]
outputs: [research/runtime.mjs, research/coordinator.mjs, docs/VALIDATION.md]
status: done
human_gate: none
---

Review tightened observed openings to the complete captured first line, rejecting one-character
prefixes. Unpinned approved collection selects the active approved profile despite a newer draft;
pinned synthesis still checks its exact version. Extended existing integration cases for both.
All29 focused research tests passed again after these changes. Documents clarify structured guards
do not verify factual/metric claims embedded in prose; human source and editorial review remain.
No paid calls or business approvals occurred.
