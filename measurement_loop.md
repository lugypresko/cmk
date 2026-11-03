# Measurement loop

Goal: learn what produces the **two success metrics**, **ICP conversations** and **time saved**, and feed that back into topic choice, formats, channels and timing. **It never feeds Guardian scores.** Reach, likes and viewer data never raise `brand_score` or `icp_relevance_score` (guardian_rules.md §3).

Tables: `performance_logs` (v0 + migration 002 columns), `measurement_reviews`, `correction_log`, `prompt_versions`.

## 1. Capture windows
For every published piece, `performance_logs` gets one snapshot row per window:

| window_label | when | why |
|---|---|---|
| `24h` | published_at + 24h | early signal (hook) |
| `72h` | + 72h | most LinkedIn/X engagement is in by then |
| `7d` | + 7d | comments / DMs that trickle in |
| `14d` | + 14d | end of the rotation the piece ran in |
| `lifetime` | when the plan closes | final number |

`source`: `import` for platform exports (e.g. the LinkedIn xlsx), `api` later, `manual` for whatever Itay enters.

## 2. Metrics per format
| format | primary | secondary |
|---|---|---|
| text_post, carousel, infographic, x_thread | comments, comment rate = comments / impressions | reactions, shares, saves, profile_visits |
| reel, short, broll, avatar | completion_rate, avg_watch_s | views, comments, shares |
| poll | poll_votes, comments | follow-up post performance |
| interactive_story | story_interactions / views | replies |
| email | replies, email_clicks / email_sent | opens (directional only), unsubscribes (guardrail) |
| all | **icp_conversations**, **time_saved_minutes** | icp_reach_share (aggregate) |

## 3. Success metrics (human-confirmed)
- **icp_conversations**: DMs, calls or comment threads with someone who fits `icp_profiles` (EM / Group Manager / Director in growing B2B SaaS) that started from the piece. Itay enters or confirms it (`confirmed_by`). Agents may *suggest* candidates from comment threads, but never count them on their own.
- **time_saved_minutes**: compares against Itay's manual baseline per format. Itay sets the baseline once; it is **not known yet**. Time saved = baseline − (Itay's review and edit minutes on the piece). The review minutes come from Itay's log, or from `audit_log` timestamps between `in_review` and `approved` as an upper bound.
- Neither metric is ever invented or extrapolated (agents.md, Measurement row).

## 4. Weekly loop (and at the end of each 14-day plan)
```
1. IMPORT   new exports → performance_logs (dedupe on content_id + captured_at)
2. JOIN     piece → core_asset → core_insight (topic, pattern_name, tags)
            piece → format, channel, language, hook pattern, prompt_version_id, rotation slot/time
3. AGGREGATE (min n = 3 pieces per cell, otherwise "insufficient data")
            by topic/pattern, format×channel, language, posting window, hook pattern, prompt_version
            rank on: icp_conversations per piece, then comment rate (or the format's primary metric)
4. COMPARE  against the previous review; flag changes > 1 std dev or ≥ 2× (small-n caution)
5. PROPOSE  measurement_reviews.proposals[], each {target, change, evidence, status:'proposed'}:
            target ∈ topic_queue | scheduler_windows | format_mix | daily_caps | prompt_versions | format_specs
            e.g. "raise decision-dependency topics in queue", "move linkedin EN window to 07:45"
6. REVIEW   Itay accepts or rejects each proposal → status approved/rejected
7. APPLY    accepted changes become new versions (format_specs.version+1, prompt_versions.version+1,
            next rotation_plans.constraints). Never an in-place edit of an active row.
```

## 5. What feeds where
| signal | feeds | never feeds |
|---|---|---|
| ICP conversations by topic | ResearchAgent topic queue, Scheduler `topic_signal` | Guardian ICP score |
| comment rate / completion by format×channel | Scheduler `format_channel_fit`, `daily_caps` proposals | Guardian brand score |
| best posting windows | Scheduler `H` | n/a |
| prompt_version deltas | prompt_versions proposals (A/B only on equal topics) | thresholds |
| correction_log repeats (≥3) | brand_voice / format_specs / prompt versions (existing rule) | n/a |
| viewer companies / names (analytics) | **nothing** (internal only, B-12) | content, leads files |

## 6. Guardrails
- Small numbers: one post (e.g. the Stripe Minions seed, 27 comments vs 15 reactions) is a **hypothesis**, never a rule.
- Unsubscribes, negative comments or a pulled piece get flagged in the review. Nothing changes automatically.
- `icp_reach_share` stores aggregates only. Rows don't carry individual viewer data.
