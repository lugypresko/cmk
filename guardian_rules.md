# CMK Guardian Rules v0 — The Push / Itay Foyerstein

`guardian(piece) -> GuardianReport` (see `contracts.md`). Machine-checkable twin: `guardian_checklist.json` (same check ids).
Source of truth: https://itayfoyerstein.com. Promise: *Your team can do the work. The decisions still come back to you.*

Guardian **reads** the active `brand_voice`, the target `icp_profiles` row, `approved_facts` (status=`approved` AND confidentiality=`public` only), the active `format_specs` row for (format, channel, language), and `past_content` exemplars / anti-examples. It never reads other sources for facts. It never sets `approved`, `scheduled`, `published`, or `approved_by`.

---

## 0. Order of evaluation (the rule stack)

1. **Schema** — validate against `cmk/ContentPiece` or `cmk/CoreAsset`. Invalid → blocker `S-01`, stop.
2. **Blockers** (§1) — run all of them; collect every hit (don't stop at the first).
3. **Format** (§4) — per `format_specs` + LinkedIn limits.
4. **Language** (§5).
5. **Claims vs approved_facts** (§6) → fills `unsupported_claims`.
6. **Confidentiality** (§7).
7. **CTA** (§8).
8. **Score** `brand_score` (§2) and `icp_relevance_score` (§3), apply penalties from checks, clamp 0–100.
9. **Verdict** (§9).

## 1. Blockers (hard fail → `needs_changes`, whatever the score)

| id | Blocker | Example that trips it |
|---|---|---|
| B-01 | Factual claim (number, %, multiplier, credential, outcome, third-party stat) with no matching approved+public `approved_facts` row in `fact_ids` | "Stripe merges N PRs a week" with no `proof.*` fact row; "30 years" when the fact says 25+ |
| B-02 | Pricing, fees, discounts, packages-with-price, "free" offers | "₪…/session", "20% off", "free first session" |
| B-03 | Client name, client's employer, or any company named as a coaching client / case source | "a Director at monday.com told me in our session…" |
| B-04 | Testimonial or attributed quote that isn't from an approved `core_insights` row (origin `conversation`/`session_observation`, confidentiality ≠ `private`) and isn't anonymized | invented "'This changed my team' — VP R&D" |
| B-05 | Confidentiality breach: identifiable case details, or implying session content is shared / reported to the funding company | role + company stage + city + team size that pins a person; "I told their CEO what we discussed" |
| B-06 | Wrong language: body language ≠ `piece.language` (see §5) | HE piece that is mostly English |
| B-07 | Guaranteed / promised outcomes | "guaranteed", "you will double velocity", "מובטח" |
| B-08 | `fact_ids` references a fact that is `draft`, `retired`, or not `public` | using `credential.hours` before Itay approves it |
| B-09 | Gate bypass: agent-written `approved_by`, or status ∉ {draft, in_review, needs_changes} written by an agent | |
| B-10 | Disparaging a named person or company | "X's engineering culture is broken" |
| B-11 | Hard format limit broken (LinkedIn text > 3,000 chars; carousel without `slides`; slides > `format_specs.max_slides`) | |
| B-12 | Uses analytics viewer data as content (viewer companies, names, individual profiles) | "people from Wix and NVIDIA read my last post" |

**Third-party public companies are not clients.** Naming a public company as a public example (e.g. Stripe and its "Minions" agents) is allowed **only** if every stated fact about it maps to an approved `proof.*` fact with a public `source_url`. The name itself is fine; unsourced numbers about it are B-01.

**Score cap:** if any blocker fires, `brand_score` is capped at 74 so a DB query on `brand_score ≥ 75` never surfaces a blocked piece. ICP score is left honest.

## 2. `brand_score` (0–100, additive, then penalties)

| Component | Max | Full points when… |
|---|---|---|
| BR-1 Evidence before diagnosis | 15 | Shows the situation/evidence first, then names the pattern. No unearned "bottleneck" label. |
| BR-2 System, not person | 10 | Names the working pattern (decision dependency, requirement authorship, gates), not a manager's flaw/confidence. |
| BR-3 Promise alignment | 15 | Ties back to "decisions still come back to you" / "needed at the right level" / what genuinely needs your judgment vs what learned to wait. |
| BR-4 Human at start and end | 10 | When AI/agents/process appear: a human owns the requirement (start) and the judgment/approval (end); machines run the middle via deterministic gates. Non-AI posts: full points if decision ownership is explicit. |
| BR-5 Evidence + numbers, traceable | 15 | At least one concrete, observable proof point (approved fact, anonymized observation, or sourced public example). 8 pts if concrete but number-free. 0 if pure opinion. |
| BR-6 One reversible move | 10 | Offers one testable move or question the reader can try this week, not a framework. |
| BR-7 Practitioner tone | 10 | Calm, direct, first-person practitioner; real trade-offs; no hype, no motivational clichés. |
| BR-8 CTA quality | 10 | See §8. |
| BR-9 Language craft | 5 | Native-sounding HE or EN (not a translation calque); consistent terms. |

**Penalties** (from checklist, `points_delta`): each `avoid_phrases` hit −10 ("just delegate more" −15); hype words (10x, crush it, game-changer, revolutionary, מהפכני) −10; advocating full autonomy with no human gate −15; >1 exclamation mark −3; generic AI-content tells ("In today's fast-paced world", "Let's dive in", "unlock") −5 each.

## 3. `icp_relevance_score` (0–100)

| Component | Max | Full points when… |
|---|---|---|
| ICP-1 Manager lens | 30 | The reader is positioned as the person who **owns a team / process / decision**: EM, Group Manager, Director ("your team", "dev manager", "who writes the requirement in your team"). |
| ICP-2 Pain match | 25 | Hits ≥1 `icp_profiles.pains` item (decision coming back, meeting you must attend, climbing escalation, work stalls when you're away, no time for strategic work) or its AI-era form (agents produce output but the decision/requirement still comes back to you). 15 if adjacent. |
| ICP-3 Leadership decision, not tooling | 20 | The point is about decisions, authority, context, relationships, process ownership. A tool/prompt tip with no leadership decision → ≤5. |
| ICP-4 Company context | 10 | Fits a growing B2B SaaS / scaling R&D org (explicit or clearly implied). |
| ICP-5 Secondary lens | 10 | A CTO / VP R&D can map it to org design or their managers. |
| ICP-6 Engineer-readable | 5 | A senior engineer can follow and act on it (plain technical terms, no manager jargon). |

**Audience rule (from the Minions analytics).** The EN Minions post reached mostly Senior/Entry engineers and founders (SE 8%, Co-Founder 6%, Founder 4%; Director 10%, Manager 7%, VP 7%, CXO 13%) and drove 27 comments on 15 reactions. Guardian does **not** chase reach:
- ICP score rewards the EM/Director angle (ICP-1 + ICP-3 = 50 pts). Reach data never raises ICP score.
- Engineer-readable is a **bonus, never a penalty** (ICP-6). Technical depth (LLM, CI, E2E, PRs) is fine.
- Penalty only when the post is **addressed solely** to ICs or founders with no team/decision owner in it: `ICP-P1` −15 ("Devs: here's my Claude prompt"). Founder/CEO-only framing ("as a solo founder…") −10 (`ICP-P2`).
- `not_a_fit` framing (missing authority, understaffing, unresolved org design presented as solvable by coaching) −10 (`ICP-P3`).

## 4. Format checks — LinkedIn

### text_post
- Hard: body ≤ 3,000 chars (B-11). `hashtags` ≤ 5 (schema); 0–3 recommended (warn >3).
- `hook` = first 1–2 lines, must equal the start of `body`; ≤ 200 chars (warn), first line ≤ 120 chars (warn). It has to work before "…see more".
- Length within `format_specs.min_chars..max_chars`; default band 600–2,200 (warn outside).
- Paragraphs ≤ 3 lines / ≤ 350 chars; no block > 600 chars without a line break (warn).
- External link in body → warn (put it in the first comment). ≤ 3 emojis (warn).
- Last paragraph = the CTA (§8). `cta` field must match the closing text.

### carousel
- `slides` required (B-11 if missing). `n` sequential from 1, no gaps (block, `F-C1`).
- Slide count 5–10 recommended (warn); > `format_specs.max_slides` (default 10) → block.
- Slide 1 = hook: headline ≤ 60 chars EN / ≤ 50 chars HE, no body text needed.
- Each slide: headline ≤ 80 chars, `text` ≤ 300 chars, one idea per slide (warn).
- Last slide = CTA question, matching `cta`.
- Every number on any slide must be in `fact_ids` (same as B-01; slides are checked like body).
- Caption (`body`) 150–1,300 chars, same language as slides.
- HE carousels: RTL rendering is PackageBuilder's job, but Guardian blocks mixed-direction headlines that start with an English token (renders badly) → warn `F-C7`.

## 5. Language (HE / EN)

- `he`: ≥ 60% of letters are Hebrew script. English tech tokens are allowed and don't count against this (LLM, AI, PR, CI/CD, E2E, SaaS, B2B, Claude, GPT, Stripe, Minions, agent, prompt, code review). < 40% Hebrew → B-06; 40–60% → warn.
- `en`: zero Hebrew characters (B-06 if any). One spelling system per piece (warn).
- HE address: plural ("אתם/אליכם", as in `cta_primary_he`) or slash forms. Masculine-only singular imperatives addressed at the reader → warn `L-03`.
- HE seed text in `brand_voice` / `icp_profiles` is `needs_review=true`. Until Itay approves it, Guardian must not require HE `say_phrases` verbatim; it scores meaning, not wording (`L-04` info).
- HE/EN twins (same `core_asset_id`): same claims and same `fact_ids`. A number in one twin and not the other → warn `L-05`. An unapproved number in either → B-01.
- Twins are adapted, not translated: different opener/anecdote is fine (see Minions HE vs EN). A literal calque costs BR-9 points.

## 6. Claim checks vs `approved_facts`

1. Extract claim candidates: digits, %, "x"-multipliers, Hebrew number words, durations ("25 years", "12 weeks"), counts ("1000+ hours", "every manager"), credentials, outcome statements ("teams that do X ship faster"), and statements about named third parties.
2. Classify each one: **fact** (needs a source), **experience** ("what I keep seeing", "every dev manager I talk to"), **opinion/question/hypothetical**.
3. A **fact** must match an approved+public fact in `fact_ids`. Numbers must equal the statement or be weaker ("25+" → "over 25" OK; → "30" fails). No match → B-01, and the exact text goes into `unsupported_claims`.
4. **Experience** generalizations are voice, not facts. If quantified ("80% of the managers I coach"), they become facts → B-01 unless approved.
5. Any `fact_ids` row not in the text → warn `C-04` (keep `content_fact_refs` honest).
6. **Third-party proofs** (Stripe Minions etc.): Research proposes `approved_facts` rows (`category='proof'`, `source_url` = the company's public post). Itay approves them. Until then, Guardian treats every Stripe number as B-01.

## 7. Confidentiality

- Allowed inputs: `core_insights.confidentiality ∈ {public, anonymized}` with status `approved`. `private` → B-05.
- Anonymize: no names, no employer, no unique combination (role + company + city + size + date). Use "a Director in a ~200-person B2B SaaS" only if it doesn't pin someone. Change non-essential details.
- Never imply that session content is shared, reported to a sponsor, or used without consent (approved fact `boundary.confidentiality`).
- Quotes from people (e.g. "a CTO who tested it told me…") need to be anonymized, generic in role, and traceable to an approved core_insight. Otherwise → B-04.
- Analytics data (viewer companies, titles, locations) is internal only → B-12.

## 8. CTA quality (BR-8, 10 pts + checks)

Good CTA = **one closing question** that makes the reader look at **their own team / decision / process** and is answerable in one comment.
- +10: specific, situational, binary or concrete open question ("Does your LLM run tasks, or manage a process?" / "Who writes the requirement in your team, and how do you know it's right?").
- +5: a question that is relevant but generic.
- 0 and warn `CTA-02`: "Thoughts?", "Agree?", "What do you think?".
- Engagement bait ("comment YES", "like if…") → warn −10 (`CTA-03`); pricing/DM-for-price → B-02.
- Max one CTA. Soft offer CTA (`cta_primary_*`: "Start with one real situation…") is allowed as a P.S. line after the question; warn if it replaces the question (`CTA-05`).
- No CTA at all → warn `CTA-01`, BR-8 = 0.

## 9. Verdict

| Condition | verdict | status written |
|---|---|---|
| Any blocker | `needs_changes` | `needs_changes` (+ `correction_log` row per blocker) |
| No blocker, brand ≥ 75 **and** ICP ≥ 70 | `pass` | `in_review` (Itay approves) |
| No blocker, brand 50–74 or ICP 40–69 | `needs_changes` | `needs_changes` |
| brand < 50 or ICP < 40 (off-strategy), or still blocked at revision ≥ 3 | `reject` | `needs_changes` + `recommend_reject=true`. Only a human sets `rejected`. |

Thresholds stay at the contract defaults (75 / 70). Reason: one calibration pair isn't enough data to move them. Revisit after 20+ scored `past_content` rows and correction_log promotions.

## 10. Calibration: Stripe Minions exemplars

Run Guardian on both seeds (import full bodies into `past_content`, `is_exemplar=true`) **before** any generation. Expected band:

| | brand | ICP | Why |
|---|---|---|---|
| HE "משימות מול תהליך E2E" | 85–92 | 75–85 | Direct practitioner opener; systems pattern (tasks vs process); human at start/end + deterministic gates; Stripe proof; binary CTA "ה-LLM שלכם עושה משימות, או מנהל תהליך?" Slightly lower ICP: the question is team/process level but more tool-flavored. |
| EN "Human oversight… (Minions)" | 85–92 | 80–88 | "Every dev manager I talk to" = manager lens (ICP-1 full); WHAT in message / HOW in system = decision ownership; CTA on requirement authorship = leadership decision. |

Acceptance: both ≥ 75/70 with **zero blockers once Stripe proof facts are approved**. If Guardian scores them lower, fix the scorer, not the threshold.

**What would fail them:**
- Stripe numbers kept, but no approved `proof.stripe_minions.*` facts → B-01 (expected today: those facts aren't seeded yet).
- The "CTO tester" quote attributed with name/company, or not traceable to an approved core_insight → B-04/B-05.
- Rewritten as "Devs, 10x your output with Claude agents" → hype −10, ICP-P1 −15, ICP-1/ICP-3 ≈ 0 → ICP < 40 → reject.
- Removing the human ends ("let agents ship straight to prod") → −15, BR-4 = 0.
- CTA swapped for "Thoughts?" → BR-8 = 0 + warn.
- HE version with mostly English sentences → B-06.
- Mentioning which companies read the post (monday.com, Wix… from analytics) → B-12.

High comment count (27 comments vs 15 reactions) is a **Measurement** signal for topic choice. It never feeds the Guardian score.

## 11. v1 pointers (SPEC formats, thresholds)

- Thresholds: scores are stored as integers from 0 to 100, with 0–1 float mirrors. The active profile lives in `cmk.guardian_thresholds`: `v0` = 75/70 (active), `spec_v1` = 0.85 (inactive, needs review). See `guardian_thresholds.md`. The §9 verdict uses the active profile's numbers, and the blocked cap is `brand_min − 1`.
- New formats: checks for `x_thread`, `broll`, `reel`, `short`, `infographic`, `poll`, `interactive_story`, `email` and `avatar` **aren't written yet**. Each format's stub `format_specs.rules` (`migrations/003`) lists the intended checks. Before enabling a format, add its F-* checks to `guardian_checklist.json` (v2). Proposed new ids: F-V1 (beats contiguous, block), F-P1 (poll limits, block), F-I1 (alt text, block), B-13 (avatar without approved consent fact or AI disclosure, block), B-14 (email to a non-opted-in segment, block).
- Every text field in `payload` gets scanned like `body` (claims, language, confidentiality).
