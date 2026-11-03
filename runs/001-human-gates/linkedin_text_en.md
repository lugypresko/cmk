# LinkedIn text_post (EN) — run 001 · human-gates

```yaml
contract: cmk/ContentPiece
format: text_post
channel: linkedin
language: en
revision: 2
parent_id: null
status: in_review
created_by: agent
approved_by: null
hashtags: []            # recommend none (0–3 allowed)
fact_ids: []
pending_fact_keys: [proof.stripe_minions.pattern]   # only if Stripe paragraph is kept
hook: "The agent finished the PR.
Then it waited for your \"one last look\"."
cta: "In your team's flow, where does the human sit: at the start and the end, or in the middle of every step?"
```

**Two variants, same text:**
- **Variant A** = full text below, including the paragraph marked ⟦STRIPE⟧. Blocked (B-01) until Itay approves `proof.stripe_minions.pattern`.
- **Variant B (pass-ready)** = delete the ⟦STRIPE⟧ paragraph. No other changes.

## Post text

```text
The agent finished the PR.
Then it waited for your "one last look".

I keep hearing this from dev managers. Not because the agents are bad. Because nobody moved the checks.

That same look shows up on design and syncs — the agents produce more, so more lands on the same desk. The design still waits for a sync you have to attend.

Before naming it, look at where the human sits in the flow. In many teams, the manager sits in the middle: reviewing steps, approving drafts, answering "is this OK?" in Slack.

Accountability quietly turned into being present.

The pattern worth testing is the reverse:
→ Start: a human owns the requirement. What we're solving, what "done" means, what must not break.
→ Middle: deterministic gates. Lints, tests, a checklist with a clear threshold. Same answer every time, and they don't wait for anyone's calendar.
→ End: a human owns the judgment. Not "did it pass?" but "is this right, and do we ship it?"

⟦STRIPE⟧ Stripe has written publicly about its "Minions" coding agents with this shape: a person writes the task, deterministic steps like linters and tests run in between, and a human reviews the pull request.

One move for this week: take one review that keeps coming back to you. List what you actually check. Mark each item as a rule (same answer for anyone) or judgment (needs context only you hold). Gate the rules. Keep the judgment, at the end.

The goal isn't to be needed less. It's to be needed at the right level.

In your team's flow, where does the human sit: at the start and the end, or in the middle of every step?
```

**First comment (optional, Variant A only):** Stripe's post on Minions: https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents

<!-- revision 2, 2026-11-03: body opens with approved PR hook; removed duplicate "same desk" sentence and orphaned "That same look" referent -->

## Approval
- status: in_review (Variant B) — revision 2 awaiting Itay re-approval after body fix
- previous: revision 1 approved 2026-11-03 (Variant B, PR hook in frontmatter only; body still used old opener)
- hook: PR scene
- next: Itay re-approves EN; Day 1 schedule uses HE only
