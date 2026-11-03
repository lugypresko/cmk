# Guardian thresholds: 0–100 scores and the SPEC's 0.85

## TL;DR
- **The stored truth is integers from 0 to 100.** Those live in `brand_score` and `icp_relevance_score`, as today. Every existing CHECK, the checklist, and the run 001 reports keep working.
- **0–1 floats are derived and never stored on their own.** `brand_score_float = brand_score / 100.0`, and the same goes for ICP. They're generated columns from migration 002 on `content_library` and `core_assets`. `0.85 ≡ 85`.
- **There are two threshold profiles** in `cmk.guardian_thresholds`, and exactly one is active:

| profile | brand_min | icp_min | float | blocked cap | active | status |
|---|---|---|---|---|---|---|
| `v0` | 75 | 70 | 0.75 / 0.70 | 74 | **yes** | current gate (contracts.md, checklist v1) |
| `spec_v1` | 85 | 85 | 0.85 / 0.85 | 84 | no | SPEC v1.0. `needs_review`: whether 0.85 also applies to ICP is an **assumption** |

## Input normalization (accept both, store one)
An agent or tool may report a score on either scale. It has to say which one with `score_scale`. Guardian never guesses from the value, because `1` would be ambiguous.

```
pct = cmk.score_to_pct(value, 'float_0_1')   -- 0.85 -> 85, 0.849 -> 85 (round half up), 1.2 -> NULL (reject)
pct = cmk.score_to_pct(value, 'pct_0_100')   -- 85 -> 85, 101 -> NULL (reject)
```
- A `NULL` result is invalid input, so the report gets blocker `S-01`.
- When a report carries both `brand_score` and `brand_score_float`, they must agree: `abs(brand_score/100 - brand_score_float) < 0.005`. Otherwise it's S-01.
- Comparisons always run on the integer: `brand_score >= brand_min`. Don't compare floats, because rounding is the trap there.

## Verdict with a profile
```
t = active guardian_thresholds row        (report.threshold_profile = t.profile)
blocked          -> needs_changes, brand_score capped at t.brand_cap_when_blocked
brand >= t.brand_min AND icp >= t.icp_min -> pass -> in_review (Itay approves)
brand <  t.reject_brand_below OR icp < t.reject_icp_below -> reject (needs_changes + recommend_reject)
otherwise        -> needs_changes
```
The blocked cap moves with the profile (`brand_min − 1`). That way a query like `brand_score >= brand_min` never returns a blocked piece, whichever profile is active.

## Why v0 stays at 75/70 for now
- The only scored data is run 001's **self-estimates** (`runs/001-human-gates/guardian_self_check.md`), not a real Guardian run. Variant B came in at about 81–84 brand and 80–85 ICP. Under `spec_v1` (85/85), **most of the approved run 001 pieces would score `needs_changes`**. One estimate doesn't justify that.
- The rule in `guardian_rules.md` §9 still holds: revisit after 20+ scored `past_content` rows. If good, already-approved posts score below 85, fix the scorer first and only then raise the bar.

## Switching to spec_v1 (human only)
1. Confirm with Itay how the SPEC means 0.85: (a) for both scores, (b) for brand only, or (c) for a single combined score. If it's (c), add `combined_min` and define the weights. The SPEC text needed for that is missing (`SPEC.md`).
2. Run Guardian over at least 20 `past_content` exemplars and the run 001 pieces under both profiles. Write up the deltas.
3. Have Itay approve: `UPDATE guardian_thresholds SET approved_by='Itay', approved_at=now(), needs_review=false WHERE profile='spec_v1';`, then flip `is_active` in one transaction. The `audit_log` trigger records it as `threshold_change`.
4. Already-approved pieces keep their approval. `guardian_threshold_profile` on each row records which bar they passed.

Agents may **never** change thresholds. That's in agents.md, and every change shows up in audit_log.
