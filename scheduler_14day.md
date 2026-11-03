# Scheduler: 14-day rotation algorithm

Tables: `rotation_plans`, `rotation_slots`, `content_library.rotation_*` (migration 002). Contracts: `cmk/RotationPlan`, `cmk/RotationSlot` (contracts.md). Timezone: **Asia/Jerusalem** (UTC+2 in winter, UTC+3 in summer). Always store `timestamptz`.

## Principles (trust-first)
1. **Only `approved` pieces get scheduled.** The DB CHECK and the format-enabled trigger enforce this.
2. **The Scheduler proposes, Itay confirms.** It writes `scheduled_at` / `status='scheduled'` only to carry out a logged human confirmation (`rotation_slots.confirmed_by`, `audit_log`).
3. **Volume is a cap, not a goal.** The SPEC aims for about 100 pieces/day across all formats and channels. Each plan reaches that through `daily_caps`, which ramp up as formats get enabled. v0 cap: `{"linkedin": 1}`.

## Inputs
- `P`: the plan (`start_date`, `days=14`, `daily_caps`, `constraints`)
- `A`: candidate pieces, `status='approved'`, `format_registry.v0_enabled`, packaged (PackageBuilder done), not in another active plan
- `E`: evergreen pieces (`is_evergreen`, `status='published'`, `last_published_at <= start_date - recycle_after_days`)
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
     pool = A ∪ recycle_candidates(E)          # recycled = NEW revision (see §Recycling)
     score each piece:
        s = 0.40*topic_signal(core)            # measurement_loop: ICP conversations, comment rate
          + 0.25*freshness(piece)              # newer approved first; evergreen decays
          + 0.20*format_channel_fit(format, channel)  # from performance_logs, default 0.5
          + 0.15*icp_score_norm(piece)         # icp_relevance_score/100. Reach never counts
  3. FILL (greedy, highest s first; tie → oldest approved_at)
     for piece in pool sorted desc:
        for slot in open slots where slot.channel == piece.channel
                                 and (slot.format is null or == piece.format)
                                 and (slot.language is null or == piece.language), earliest first:
           if violates(C, slot, piece): continue
           assign; break
  4. REPAIR
     - language_mix / format_mix off by >1: swap pieces between slots of the same channel
       when both swaps stay valid
     - leftover open slots stay open (never filled with unapproved or off-format pieces)
  5. VALIDATE (hard; any failure blocks the proposal)
     - every filled slot has a piece that is approved and packaged, and its format is enabled
     - no cap is exceeded; no constraint is violated
     - no piece appears twice in the plan (unique index rotation_slots_one_piece_per_plan)
  6. PROPOSE
     plan.status = 'proposed'; write rotation_slots (status 'filled', rationale per slot)
     emit a summary for Itay: per day × channel table, open slots, constraint near-misses
```
`violates(C, slot, piece)` checks the same-core spacing (both rules), the min gap, and evergreen share. It also enforces **the v0 rule of at most 1 LinkedIn post/day**.

## Human confirmation (two modes)
- **v0 (today): per slot.** Itay confirms each slot. Then the Scheduler sets `rotation_slots.status='confirmed', confirmed_by, confirmed_at` and `content_library.status='scheduled', scheduled_at, rotation_plan_id, rotation_slot_id, rotation_slot=day`.
- **Later: batch.** Itay approves the whole plan (`rotation_plans.status='approved', approved_by, approved_at`). That confirms every filled slot in one transaction, and each slot still gets its own audit row. A slot that changes after approval (a swap or a new piece) falls back to `filled` and needs its own confirmation.

## Re-planning during a running plan
- When a piece gets pulled (Itay, a Guardian re-check, or a factual change), its slot goes to `skipped` or `open`. The Scheduler may propose a replacement, and that replacement needs confirmation.
- Published slots are immutable.
- On day 11 the Scheduler drafts the next plan (`previous_plan_id`), so Itay gets 3 days to review it.

## Recycling (evergreen)
- Only pieces that **Itay** flagged `is_evergreen=true`, published at least `recycle_after_days` ago (≥ 14), with no `retired` facts in `content_fact_refs`.
- A recycle creates a **new content_library row**: `recycled_from_id`, a new hook/opener (Repurposer), `revision` +1, status `draft`. Then it runs **Guardian and Itay approval again**. A verbatim repost isn't allowed: facts may have changed, and platforms penalize duplicates.

## Outputs
- `rotation_plans` + `rotation_slots` rows (the proposal)
- After confirmation, `content_library.scheduled_at/status` updates. Every transition goes to `audit_log`.

## Not decided (needs SPEC text / Itay)
- the real per-channel caps that get to ~100/day, and which channel carries which share
- whether the Distributor auto-posts confirmed slots (needs platform API access) or Itay posts manually (the v0 default)
- holiday calendar and quiet hours
