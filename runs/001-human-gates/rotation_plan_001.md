# Rotation Plan 001 (ACTIVE — Day 1 confirmed), 14 days, 2026-11-04 → 2026-11-17

- Status: **active**. Day 1 LinkedIn HE confirmed by Itay on 2026-11-03. Remaining slots still proposed/open. Nothing published yet (manual Distributor).
- Timezone: Asia/Jerusalem (UTC+2). daily_caps v0: `{"linkedin": 1}`. Window: LinkedIn 08:30–09:00 (default placeholder, not a researched claim).
- Calendar: Google Calendar primary (`lennyf2512@gmail.com`), color 9 (blue), all events **free/non-blocking**, no attendees, no invites.
  - Overview: https://www.google.com/calendar/event?eid=MGhnZmRwdm5kMTJzZmUxZ3ZkZWlta2xnN3MgbGVubnlmMjUxMkBt
  - Day 1 proposed slot: https://www.google.com/calendar/event?eid=dWJoZTAxNGNpb3VlY2cwdG9tMW4ycm50bmsgbGVubnlmMjUxMkBt

## Day × channel

| Day | Date | LinkedIn 08:30 | X | Instagram | YouTube | Email |
|---|---|---|---|---|---|---|
| 1 | 2026-11-04 (Wed) | **CONFIRMED**: run001 LinkedIn HE, Variant B (PR-scene hook, no Stripe). Manual publish. | n/a (cap 0) | n/a | n/a | n/a |
| 2 | 2026-11-05 (Thu) | OPEN | n/a | n/a | n/a | n/a |
| 3 | 2026-11-06 (Fri) | OPEN | n/a | n/a | n/a | n/a |
| 4 | 2026-11-07 (Sat) | OPEN | n/a | n/a | n/a | n/a |
| 5 | 2026-11-08 (Sun) | OPEN (earliest day for the run001 EN twin) | n/a | n/a | n/a | n/a |
| 6 | 2026-11-09 (Mon) | OPEN | n/a | n/a | n/a | n/a |
| 7 | 2026-11-10 (Tue) | OPEN | n/a | n/a | n/a | n/a |
| 8 | 2026-11-11 (Wed) | OPEN | n/a | n/a | n/a | n/a |
| 9 | 2026-11-12 (Thu) | OPEN | n/a | n/a | n/a | n/a |
| 10 | 2026-11-13 (Fri) | OPEN | n/a | n/a | n/a | n/a |
| 11 | 2026-11-14 (Sat) | OPEN (Scheduler drafts plan 002 today) | n/a | n/a | n/a | n/a |
| 12 | 2026-11-15 (Sun) | OPEN | n/a | n/a | n/a | n/a |
| 13 | 2026-11-16 (Mon) | OPEN | n/a | n/a | n/a | n/a |
| 14 | 2026-11-17 (Tue) | OPEN | n/a | n/a | n/a | n/a |

Filled: 1/14 confirmed · Open: 13/14. Other channels: cap 0 in v0.

EN twin: revision 2 body fixed 2026-11-03 (Guardian pass); awaiting Itay re-approval before any EN slot proposal (earliest day 5).

### Why only one slot is filled
- The pool holds only approved + packaged pieces: run001 LinkedIn HE and EN text (Variant B, approved by Itay). Core and carousel are still **draft**, so they're excluded.
- The EN twin shares a core with HE. `same_core_same_channel_days=4` means it can't run before day 5. It isn't auto-filled here. The Scheduler can propose it for day 5+ once Itay confirms day 1. (Optional next proposal: day 5, 2026-11-08 08:30.)
- No evergreen pool exists yet (nothing has been published), so recycling is n/a.
- Open slots stay open. The Scheduler never invents pieces.
- Weekend/holiday handling: `quiet_days=[]`. Itay hasn't set any, and nothing is assumed (Fri/Sat slots stay open until Itay sets quiet days).

## Constraints used (scheduler_14day.md defaults)
| key | value |
|---|---|
| same_core_same_channel_days | 4 |
| same_core_any_channel_per_day | 2 |
| min_gap_minutes_same_channel | 180 |
| language_mix | he 0.5 / en 0.5 (target over plan) |
| format_mix_max_share | 0.5 |
| evergreen_max_share | 0.3 |
| quiet_days | [] |
| v0 LinkedIn max/day | 1 |

## Target map (~100/day), a CAPACITY MAP and not a publish list
14 all-day calendar events ("CMK target map · day N/14") show the reuse goal. Every number is a **target when enabled**, not live volume, and comes with no performance claims:
X ~40 · Instagram ~30 · YouTube Shorts ~12 · LinkedIn ~10 (v0 cap 1) · Email ~8 ≈ 100/day. Evergreen recycles ≤30% (each one needs a new revision + Guardian + Itay approval). Real per-channel caps are still undecided (SPEC/Itay).

## Human gate
- Day 1 LinkedIn HE: **confirmed** by Itay 2026-11-03. Treat as scheduled for 2026-11-04 08:30 Asia/Jerusalem. Manual post.
- No auto-publish. The Distributor/Zernio isn't invoked.
- Calendar event updated to CONFIRMED (one-way view of this plan).
