# LinkedIn carousel (EN) — run 001 · human-gates

```yaml
contract: cmk/ContentPiece
format: carousel
channel: linkedin
language: en
revision: 1
status: draft
created_by: agent
approved_by: null
hashtags: []
fact_ids: []
pending_fact_keys: [proof.stripe_minions.pattern]   # slide 6 only
cta: "Where does the human sit in your team's flow: at the start and the end, or in the middle of every step?"
slide_count: 8
```

## Slides

**1 — More AI output. Same decisions on your desk.**
Where the human sits in the flow matters more than which model you use.

**2 — Look at where you sit today**
Reviewing intermediate steps. Approving drafts. Answering "is this OK?" in Slack. Accountability quietly turned into being present.

**3 — Start: a human owns the requirement**
What we're solving. What "done" means. What must not break. The WHAT lives in the message; the HOW lives in the system.

**4 — Middle: deterministic gates**
Lints, tests, a checklist with a clear threshold. Same answer every time. Agents can be creative inside them. The gates don't wait for anyone's calendar.

**5 — End: a human owns the judgment**
Not "did it pass?" The gates answered that. The question is "is this the right thing, and do we ship it?" That's where you're needed.

**6 — A public example of the shape** ⟦NEED_APPROVED_FACT: proof.stripe_minions.pattern⟧
Stripe has written about its "Minions" coding agents: a person writes the task, deterministic steps run in between, a human reviews the pull request.
> *Fallback if the fact isn't approved:* headline **"Rule or judgment?"** — text: "If a check gives the same answer for anyone, it's a rule. Gate it. If it needs context only you hold, it's judgment. Keep it, at the end."

**7 — One move for this week**
Take one review that keeps coming back to you. List what you check. Mark each item: rule or judgment. Gate the rules. Move the judgment to the end.

**8 — Where does the human sit in your flow?**
At the start and the end, or in the middle of every step? Tell me in the comments.

## Caption (body)

```text
Your team brought in agents. Output went up, and the decisions still come back to you.

Often that's not the agents. It's that nobody moved the checks, so the manager still sits in the middle of every step.

The pattern worth testing: a human at the start (the requirement), deterministic gates in the middle, a human at the end (the judgment).

The goal isn't to be needed less. It's to be needed at the right level.

Where does the human sit in your team's flow: at the start and the end, or in the middle of every step?
```
