---
id: 2026-11-03_011
ts: 2026-11-03T15:21:13.213978+02:00
agent: Orchestrator
workflow: ops
action: add_ErrorWatcher
inputs: ["Itay request: monitoring + who fixes mistakes"]
outputs: ["agents.md#ErrorWatcher", "journal/entries/2026-11-03_011_errorwatcher_added.md"]
status: done
human_gate: none
notes: ErrorWatcher proposes rule promotions from correction_log; never auto-publishes or auto-promotes.
---

# ErrorWatcher added

Monitors Guardian failures, repeated corrections, Measurement anomalies. Writes proposals into Memory as new versions. Itay approves promotions.
