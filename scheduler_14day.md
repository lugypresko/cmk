# Scheduler: 14-day rotation algorithm

Tables: `rotation_plans`, `rotation_slots`, `content_library.rotation_*` (migration 002). Contracts: `cmk/RotationPlan`, `cmk/RotationSlot` (contracts.md). Timezone: **Asia/Jerusalem** (UTC+2 in winter, UTC+3 in summer). Always store `timestamptz`.

## Principles (trust-first)
1. **Only `approved` pieces get scheduled.** The DB CHECK and the format-enabled trigger enforce this.
2. **The Scheduler proposes, Itay confirms.** It writes `scheduled_at` / `status='scheduled'` only to carry out a logged human confirmation (`rotation_slots.confirmed_by`, `audit_log`).
3. **Volume is a cap, not a goal.** The SPEC aims for about 100 pieces/day across all formats and channels. Each plan reaches that through `daily_caps`, which ramp up as formats get enabled. v0 cap: `{"linkedin": 1}`.

## Inputs
- `P`: the plan (`start_date`, `days=14`, `daily_caps`, `constraints`)
- `A`: candidate pieces, `status='approved'`, `format_registry.v0_enabled`, packaged (PackageBuilder done), not in another active plan. An exact-repeatable piece that already has a slot is not in this pool; it comes back through `R`.
- `E`: evergreen pieces that are **not** exact-repeatable (`is_evergreen`, `status='published'`, `last_published_at <= start_date - recycle_after_days`). These are candidates for a **new revision**, not for a copy of the old row.
- `R`: exact-repeat rules on a LinkedIn `text_post` or `carousel` (`is_exact_repeatable`, `repeat_every_days` default 14, `repeat_until`, `max_repeats`, `repeat_approved_content_hash`, `repeat_asset_hashes`). Itay sets `repeat_until` and `max_repeats` together when he marks the piece.
- `H`: posting-time windows per channel × language. These come from `performance_logs` (measurement_loop.md §4). Until there's data, use the defaults below.
- `C`: constraints (defaults; the house choices are listed here, tune them later):

| key | default | meaning |
|---|---|---|
| `same_core_same_channel_days` | 4 | the same `core_asset_id` doesn't repeat on one channel within N days |
| `same_core_any_channel_per_day` | 2 | max pieces from one Core on a single day, across all channels |
| `min_gap_minutes_same_channel` | 180 | spacing between posts on one channel |
| `language_mix` | `{"he":0.5,"en":0.5}` | target share per channel over the plan (±1 piece) |
| `format_mix_max_share` | 0.5 | no format takes more than half of one channel's slots |
| `evergreen_max_share` | 0.3 | recycled pieces take at most 30% of slots |
| `quiet_days` | `[]` | e.g. holidays. Itay sets them; nothing is assumed |
| `default_windows` | linkedin `08:30`, x `09:00 / 13:00 / 18:00`, instagram `19:00` | placeholders until there's data. **Not a researched claim** |

## Algorithm
```
build_plan(P):
  1. GRID
     for day in 1..14, for channel, n in P.daily_caps:
        if date(day) in quiet_days: continue
        create n open slots (slot_index 1..n), local_time from H[channel] spaced by min_gap
  2. POOL
     fresh = A                                     # not already in an open plan
     repeats = exact_repeat_due(R)                 # SAME content_id and revision (see §Recycling)
     # repeats do not use the open-plan exclusion or the 4-day same-core gap
     # E is not copied into the pool. A non-exact evergreen waits for a new revision.
     score each fresh piece:
        s = 0.40*topic_signal(core)            # measurement_loop: ICP conversations, comment rate
          + 0.25*freshness(piece)              # newer approved first; evergreen decays
          + 0.20*format_channel_fit(format, channel)  # from performance_logs, default 0.5
          + 0.15*icp_score_norm(piece)         # icp_relevance_score/100. Reach never counts
  3. FILL (exact repeats first, on the earliest open day on or after their due date;
            then fresh pieces, highest s first; tie → oldest approved_at)
     for piece in repeats, then fresh sorted desc:
        for slot in open slots where slot.channel == piece.channel
                                 and (slot.format is null or == piece.format)
                                 and (slot.language is null or == piece.language), earliest first:
           if piece is an exact repeat:
              skip the 4-day same-core check and the open-plan exclusion
              still require due date, repeat_until, max_repeats, quiet day, daily cap, hash and facts
           else if violates(C, slot, piece): continue
           assign; break
  4. REPAIR
     - language_mix / format_mix off by >1: swap pieces between slots of the same channel
       when both swaps stay valid
     - leftover open slots stay open (never filled with unapproved or off-format pieces)
  5. VALIDATE (hard; any failure blocks the proposal)
     - every filled slot is packaged, its format is enabled, and the revision is still the approved one
       (an exact repeat may already be published)
     - no cap is exceeded; no constraint is violated
     - no piece appears twice in the plan (unique index rotation_slots_one_piece_per_plan)
  6. PROPOSE
     plan.status = 'proposed'; write rotation_slots (status 'filled', rationale per slot)
     emit a summary for Itay: per day × channel table, open slots, constraint near-misses
```
`violates(C, slot, piece)` checks the same-core spacing (both rules), the min gap, and evergreen share. It also enforces **the v0 rule of at most 1 LinkedIn post/day**.

**Exact-repeat exception.** For a due exact-repeat slot the 4-day `same_core_same_channel_days` rule and the "already in an open plan" exclusion do not apply. The repeat interval (`repeat_every_days`, default 14), `repeat_until`, `max_repeats`, quiet days, the LinkedIn daily cap, and the hash/fact checks still apply. The stored constraint values are not lowered. Quiet days stay the manual `quiet_days` list. Hebrew holidays are not filled in automatically.

## Human confirmation (two modes)
- **v0 (today): per slot.** Itay confirms each slot. Then the Scheduler sets `rotation_slots.status='confirmed', confirmed_by, confirmed_at` and `content_library.status='scheduled', scheduled_at, rotation_plan_id, rotation_slot_id, rotation_slot=day`.
- **Later: batch.** Itay approves the whole plan (`rotation_plans.status='approved', approved_by, approved_at`). That confirms every filled slot in one transaction, and each slot still gets its own audit row. A slot that changes after approval (a swap or a new piece) falls back to `filled` and needs its own confirmation.

## Re-planning during a running plan
- When a piece gets pulled (Itay, a Guardian re-check, or a factual change), its slot goes to `skipped` or `open`. The Scheduler may propose a replacement, and that replacement needs confirmation.
- Published slots are immutable.
- On day 11 the Scheduler drafts the next plan (`previous_plan_id`), so Itay gets 3 days to review it.

## Recycling
Two paths. They are not interchangeable.

### Exact repeat (locked 2026-11-03 20:35 Asia/Jerusalem)
Itay marks one approved LinkedIn `text_post` or `carousel` with `is_exact_repeatable`. He sets both `repeat_until` and `max_repeats` at that moment, and the row stores `repeat_approved_content_hash` plus `repeat_asset_hashes` (sha256; `[]` when there is no asset). `repeat_every_days` defaults to 14 and cannot be shorter.

The scheduler proposes the **same** `content_id` and revision on the first open day of a later plan that is at least `repeat_every_days` after the previous slot. Each appearance is its own `publish_instance` with that same `sent_content_hash`, so the existing idempotency key and the D3 unknown-refusal still apply. `repeats_done` increments when a later appearance is confirmed live. The repeat stops when the slot date passes `repeat_until` or when the published repeats reach `max_repeats`, whichever comes first.

The scheduler **blocks** the repeat, and does not revoke the approval (D2), when:
- `edited_after_approval` is set, or the live `content_hash` differs from `repeat_approved_content_hash`
- the pass-QA asset checksums differ from `repeat_asset_hashes`
- any referenced fact is outside `usable_facts_v` (not approved, not public, `valid_until` passed, or `retired`)

A blocked repeat is not filled. It is reported on the proposal as `blocked_exact_repeats`.

### New revision (everything else)
A piece Itay flagged `is_evergreen` but did **not** mark exact-repeatable, and any refresh after the facts change, still goes through a new row: `recycled_from_id`, a new hook/opener (Repurposer), `revision` +1, status `draft`, then Guardian and Itay approval again. The scheduler lists those ids as `new_revision_candidates`. It does not create the row and it does not put the old `content_id` back on the calendar.

## Outputs
- `rotation_plans` + `rotation_slots` rows (the proposal)
- After confirmation, `content_library.scheduled_at/status` updates. Every transition goes to `audit_log`.

## Not decided (needs SPEC text / Itay)
- the real per-channel caps that get to ~100/day, and which channel carries which share
- whether the Distributor auto-posts confirmed slots (needs platform API access) or Itay posts manually (the v0 default)
- holiday calendar. Quiet days stay a manual `quiet_days` list; Hebrew holidays are not inferred. Quiet hours are unset.
