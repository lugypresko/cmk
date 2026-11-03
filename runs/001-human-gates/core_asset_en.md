# Core Asset (EN) — run 001 · human-gates

```yaml
contract: cmk/CoreAsset
core_insight: "Human at the start and end; deterministic gates in the middle"   # chosen by Itay (human gate #1)
primary_language: en            # HE twin: core_asset_he.md (adapted, not translated)
status: draft                   # agent may only write draft
created_by: agent
approved_by: null
icp_profile: eng-leader-growing-b2b-saas
brand_voice_version: 1
fact_ids: []                    # no approved facts used; see markers below
pending_fact_keys:
  - proof.stripe_minions.pattern   # NEED_APPROVED_FACT (qualitative only, no numbers)
pending_confirmations:
  - ITAY_CONFIRM: own content pipeline anecdote (paragraph marked below)
```

## Title
Human at the start and the end. Deterministic gates in the middle.

## Thesis (≤280)
When agents and capable people do the work, a manager's judgment belongs at two points: defining what "right" means at the start, and judging the result at the end. Everything in between should run through gates that give the same answer every time, and don't need you.

## Body

A pattern I keep hearing from dev managers who brought agents into their teams: output went up, and the decisions still came back to them.

Not because the agents are bad. Because nobody moved the checks. The PR still waits for the manager's "one last look". The design still waits for a sync the manager has to attend. The agents produce more, so more lands on the same desk.

That's the evidence. Before giving it a name, look at where the human actually sits in the flow. In many teams I talk to, the manager sits in the middle: reviewing intermediate steps, approving drafts, answering "is this OK?" in Slack. Accountability quietly turned into being present.

The pattern worth testing is the reverse: a human at the start, a human at the end, deterministic gates in the middle.

**The start.** A human owns the requirement: what we're solving, what "done" looks like, what must not break. This is the expensive part, and it can't be handed to the model. A model will happily optimize the wrong thing, very efficiently. The WHAT lives in the message. The HOW lives in the system.

**The middle.** Gates that return the same answer every time: lints, tests, a checklist with a clear threshold, a definition of done that the pipeline or a peer can check without you. Agent loops can be as creative as they like inside those gates. The gates themselves aren't negotiable, and they don't wait for anyone's calendar.

**The end.** A human judges the result. Not "did it pass?" (the gates already answered that), but "is this the right thing, and do we ship it?" That's judgment. That's where you're needed, at the right level.

A public example of the shape: Stripe has written about "Minions", its in-house coding agents. A run starts from a task a person writes, interleaves agent loops with deterministic steps such as linters and tests, and ends in a pull request that a human reviews. ⟦NEED_APPROVED_FACT: proof.stripe_minions.pattern — source: https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents⟧ What I find useful there isn't the scale. It's the shape: humans at the edges, determinism in between.

⟦ITAY_CONFIRM⟧ I'm running my own content system the same way: I choose the insight, automated checks score every draft against written rules, and nothing goes out until I approve it.

So the question for a manager isn't "use more AI", and it isn't "hand off more". It's a design question: which of your checks are really judgment, and which are rules you've been running by hand?

**One reversible move for this week.** Take one review that keeps coming back to you. Write down what you actually check. Mark each item: *rule* (same answer every time, for anyone) or *judgment* (depends on context only you hold). Turn the rules into a gate the team or the pipeline runs without you. Keep the judgment, and move it to the end. Then watch, over the next few weeks, what still comes back and why.

If everything turns out to be judgment, that's useful evidence too. It may mean the requirement at the start was never clear enough to check against.

## Key points
1. More AI output doesn't remove the manager from the loop; it often adds more to the same desk, because the checks never moved.
2. Look at where the human sits: at the edges (requirement, judgment) or in the middle (approving every step).
3. Start: a human owns the requirement. WHAT in the message, HOW in the system.
4. Middle: deterministic gates (lints, tests, thresholded checklists) that don't wait for anyone's calendar.
5. End: a human owns the judgment: "is this right, and do we ship it?", not "did it pass?".
6. Reversible move: split one recurring review into rules vs judgment; gate the rules, keep the judgment at the end.

## CTA (closing question)
In your team's flow, where does the human sit: at the start and the end, or in the middle of every step?

*P.S. (soft offer, optional, after the question):* Start with one real situation. Bring one current decision, review, escalation or meeting that keeps coming back to you.

## Fallback if `proof.stripe_minions.pattern` is NOT approved
Replace the Stripe paragraph with:
> Some engineering orgs that run agents at scale have published their setups, and the shape is similar: a person writes the task, deterministic steps run in the middle, a person reviews the result. What matters isn't the scale. It's the shape: humans at the edges, determinism in between.

(Still a generalization about third parties — Guardian may treat it as a claim; safest fallback is to delete the paragraph entirely.)
