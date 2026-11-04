---
id: J-20261104-030
ts: 2026-11-04T15:06:03+02:00
agent: Codex
workflow: ops
action: fix-fact-support-and-manual-handoff-gates
inputs: [user-counterexamples, guardian/fact_gate.py, runtime/distributor.mjs]
outputs: [guardian/fact_gate.py, guardian/report.py, runtime/distributor.mjs, docs/VALIDATION.md]
status: done
human_gate: none
---

Confirmed the reported Hebrew direction reversal against the old code (pass/matched) and corrected
it to block/semantic_review_required. Overlap is candidate retrieval only, nonliteral wording blocks,
exact approved wording is literal support only. Extraction is incomplete; report unclassified spans
and human review rather than claiming semantic truth. Editorial source support is unverified.
Manual handoff requires a confirmed slot, scheduled approved current hash and intact matching package.
Missing/tampered/stale packages and no/unconfirmed slots create no instances or attempts. Existing
manual/unknown/exact-repeat flows pass. Fresh22 SQL steps and100 tests passed; focused Guardian25
repassed with final report assertions. No business approval, paid call, publishing or merge occurred.
