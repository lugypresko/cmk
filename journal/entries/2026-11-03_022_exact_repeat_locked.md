---
id: J-20261103-022
ts: 2026-11-03T20:35:00+02:00
agent: Codex
workflow: ops
action: lock-exact-repeat
status: done
human_gate: none
inputs:
  - SPEC_GAP.md
  - scheduler_14day.md
outputs:
  - migrations/011_exact_repeat.sql
  - runtime/scheduler.mjs
  - docs/OPERATIONS.md
---

Itay locked the D12 override at 20:35 Asia/Jerusalem. A LinkedIn text_post or carousel he marks exact-repeatable repeats that approved version every 14 days until the end date or the repeat count he sets, whichever comes first. Each repeat is a new publish_instance with the same sent_content_hash and asset checksums. The scheduler skips the 4-day same-core gap and the open-plan exclusion for that slot, and refuses the repeat when the hash drifted or a referenced fact is expired or retired. That refusal does not revoke approval (D2). Pieces he does not mark, and refreshes after facts change, still go through a new revision, Guardian, and approval. Quiet days stay manual. No new format and no auto-publish. Supersedes the H-12 default recorded in J-20261103-014 for marked pieces only.
