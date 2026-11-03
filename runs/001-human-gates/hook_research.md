# Hook research: run 001 · human-gates

```yaml
status: draft            # research only; no content piece changed
created_by: agent
approved_by: null
topic: "Human at the start and end; deterministic gates in the middle"
audience: EM / Group Manager / Director (primary), VP Eng / CTO (secondary)
sources: public web only (studies listed in §5) + Itay's own public Minions post and seed_performance_stripe_minions.json
date: 2026-11-03
```

## 1. TL;DR

- **Recommendation: switch the hook, keep its idea.** The current hook (situation → twist: "Your team brought in AI agents. Output went up. / The decisions still come back to you.") has the right tension and matches the brand promise. Its form is weak, though. The first line packs **two sentences into one line**, the weakest first-line shape in the largest 2026 dataset (NBK: 0.88 raw, **0.62 of the comment share**). It also opens on "your", which cost about 10% of reactions within the same creator in Flypost's study. And it has no concrete scene.
- **Top 3 replacements** (full list in §3):
  1. **Scene situation→twist:** "The agent finished the PR. / Then it waited for your 'one last look'." · HE: "הסוכן סיים את ה-PR. / ואז הוא חיכה ל'מבט האחרון' שלכם."
  2. **Numbered claim:** "Two places a manager belongs in an AI flow. / Everything else is a gate." · HE: "בתהליך AI יש רק שני מקומות למנהל. / כל השאר זה שערים."
  3. **First-person situation→twist:** "I keep seeing the same AI rollout. / Output goes up. The decisions still come back to the manager." · HE: "אני רואה שוב ושוב את אותה הטמעת AI. / התפוקה עולה, וההחלטות עדיין חוזרות למנהל."
- Use **#1 for the text post** and **#2 as carousel slide 1**, so the two formats can be A/B read against each other. Leave the closing question CTA as it is. The data says questions are weak **openers**. As **closers** they are neutral to slightly positive.

## 2. Findings

### 2.1 What the public 2026 data says about openers

| Pattern | Evidence | Read for this ICP |
|---|---|---|
| **Story / scene** | AuthoredUp (309,614 posts, Dec 2025 to May 2026): story hooks rank 1st of 5 (median ER 2.60%). NBK (74,119 posts): "a story, anchored in time" is the top opener (1.17). Flypost (116k posts, within-creator): a personal story adds about +33% reactions. | Strongest, but it needs a **real** moment. Invented scenes break brand voice and can trip B-04. Engineers spot fake stories quickly (Klype, CTO guide). |
| **Contrarian** | AuthoredUp: 2nd (2.31%). NBK: contrarian opener 1.09, contrarian archetype 1.09, comments 1.10. Executive Presence (6,035 exec posts): all of the top 15 opened with a statement under 15 words "that created tension before explaining anything". | Good fit for VP/CTO readers, provided the body delivers a mechanism. Avoid "bottleneck" labels (BR-1) and anything that reads as "remove humans" (penalty). |
| **Numbered claim / how-to** | NBK: opener with a number 1.12, how-to/numbered archetype 1.13 with the **highest comment index (1.33)**. MagicPost (1.18M posts): a number in the first line gets 35 vs 26 median likes. Caveat: NBK finds a number by itself is "not a lever" on the first line (0.99). The lift comes from a countable promise. | Strong for comments and saves, and it maps 1:1 to the thesis (start / middle / end). It has to be a **structural** number ("two places"), never an unapproved stat (B-01). |
| **Situation → twist** | Not labelled as its own class in the studies. It falls under "statement" (AuthoredUp 2.27%, 3rd) or "negation/contrast" (NBK 1.04 raw, 1.00 within author). It gains when it is a concrete scene, since concrete detail adds about +15% (Flypost). | This is the brand's native shape (evidence before diagnosis, BR-1). It works best when the "situation" is a recognisable artifact (a PR, a sync, a Slack "is this OK?") rather than an abstract trend. |
| **Question** | Worst opener in every dataset: AuthoredUp last (2.16%). MagicPost −34% likes. Flypost −17% reactions within the creator, worse for 69% of creators. NBK 0.88 raw, 0.94 within author. | Don't open with one. Keep the question as the **close**: NBK within-author close effects are flat to +3%, and comments run higher (1.34 to 1.55 cross-author). |

**First-line form (NBK, consistent in both cohorts):** under 40 characters scores 1.13 and over 140 scores 0.76. Four to seven words is the best band (comments 1.23). One full sentence per line beats two sentences on one line. Under 60 characters before the first line break scores 1.12. No emoji, no all-caps, no exclamation marks (zero exclamation marks 1.03, one or two 0.93). The "see more" fold is about 140 characters on mobile and about 210 on desktop, so **lines 1 and 2 together have to carry the tension.**

**Pronoun:** first person ("I/we") in the first line adds about +19% (Flypost) and 1.08 per follower (NBK). "You/your" in the first line costs about 10% (Flypost). NBK puts it at 1.09 raw but 0.98 within the author. "You" in the body helps (NBK 1.08). So: open with I or a scene, and switch to "you" once the reader is in.

**Algorithm notes (public statements only):** LinkedIn ranks on predicted dwell, skips, and "constructive conversation". It stopped counting "see more" clicks as a signal. It has published no comment weight. "Comment KEYWORD" bait has turned negative (−24% since mid-July 2026, Flypost). The hook has to stop the skip **and** earn the read. Curiosity without payoff gets marked down.

**What works for engineering leaders specifically (qualitative sources):** first-person technical *decisions* with the reasoning left in (build/buy, rewrites, incident reviews, the debt you keep). Failure and trade-off posts draw more saves and DMs from buyers. Numbered "lessons with a moral" read as AI-generated to engineers (Klype, SocialNexis). High-performing AI-agent posts open with a concrete mechanism or failure ("…and we found the leak") rather than a trend.

### 2.2 Itay's Minions post as a data point

Public page: https://www.linkedin.com/posts/itayfoyerstein_stripe-share-7518941479315070977-7PEg (seed metrics: 9,002 impressions, 5,754 reached, 15 reactions, **27 comments**, 11 saves, 0 reposts, posted 2026-10-22).

- **Hook used (HE):** "איזה פספוס ענק בעבודה עם קלוד אני רואה פה!" It is a stakes/contrarian line + first person ("אני רואה") + a named tool, 9 words / 42 characters, and it ends in "!". Then a situation→twist ("managers tell me enthusiastically… then I see what's actually built: a script here, a summary there"), concrete public proof (Stripe, numbers), and a binary question close ("ה-LLM שלכם עושה משימות, או מנהל תהליך?").
- **Data mismatch to fix:** `seed_performance_stripe_minions.json` says `language: en`, but the public text at that `post_url` is **Hebrew**. Either the metrics belong to the HE post or the URL in the seed is wrong. Check before treating it as an EN benchmark.
- **The comment count is partly self-generated.** At least 4 of the 27 visible comments are Itay's own follow-up questions (a concrete example, a counter-view, "who writes the requirement?", the Stripe link). That is a sound tactic and shouldn't be dropped, but the organic comment-to-reaction ratio is lower than 27:15 suggests. Roughly 20+ third-party comments is still strong for 15 reactions.
- **What actually drove the conversation:** substantive commenters argued about **the middle and the start**: spec detail level ("what level of detail in the Slack message?"), shift-left planning, "happy case only", agents with deterministic tools. That fits the current topic directly. People engage with *where the human sits*, not with the model.
- **Why reactions stayed low:** 15 reactions on 9k impressions is about 0.17%. The hook was a *critique of readers' practice* ("huge miss"). People comment to push back on a critique, but few "like" it. The named tool (Claude) pulled ICs: reach was mostly Senior/Entry engineers and founders, with Director 10%, Manager 7%, VP 7%. 11 saves on 15 reactions is a strong usefulness signal.
- **Lessons for run 001:** (a) keep conversation-style tension and a binary closing question. (b) **Put the manager's pain in the hook, not the tool name**, so the ICP is the one who stops scrolling. (c) Keep an engineer-recognisable artifact (a PR) so engineers still read it (ICP-6 bonus). (d) Plan 2 or 3 of Itay's own follow-up comments again (first 60 to 90 minutes). (e) Drop the "!" (brand penalty above one, NBK 0.93).

### 2.3 Current hook audit

| | EN | HE |
|---|---|---|
| Text | "Your team brought in AI agents. Output went up." / "The decisions still come back to you." | "הכנסתם סוכני AI לצוות. התפוקה עלתה." / "וההחלטות? עדיין חוזרות אליכם." |
| Pattern | situation → twist | situation → twist (+ rhetorical "?") |
| Line 1 | 47 chars, 9 words, **2 sentences** | 35 chars, 6 words, **2 sentences** |
| Strengths | Brand promise in the hook (BR-3), manager lens, calm tone | Natural HE rhythm, plural address |
| Weaknesses | Two-sentence line 1 (NBK weakest shape, comments 0.62). "You/your" opener. Abstract (no artifact). Reads as a trend statement, so the "AI rollout" opener is generic. | Same. "וההחלטות?" is a question-shaped beat that adds little. |

Verdict: decent (it would not hurt the post), but there are better options with the same meaning.

## 3. Alternative hooks, ranked (HE first, EN twin adapted, not translated)

All of them avoid unapproved numbers (B-01), client names, hype, emoji, and "!". The HE versions use plural address. Character counts are for line 1.

### #1 Scene situation→twist (recommended for the text post)
- **HE:** הסוכן סיים את ה-PR.
  ואז הוא חיכה ל"מבט האחרון" שלכם.
- **EN:** The agent finished the PR.
  Then it waited for your "one last look".
- Line 1: HE 19 / EN 26 chars, 4 to 5 words, one sentence.
- **Why #1:** It is the shortest, most concrete opener here, which hits the NBK sweet spot. It is a scene, so it gets the story/concrete-detail lift without inventing a person. The twist puts the manager's pain (the decision comes back) in front of the ICP, and "PR" keeps engineers reading. It also sets up the body's existing line "The PR still waits for your 'one last look'", so that body line can be cut or moved. Risk: "your" appears in line 2, not line 1, which is acceptable.

### #2 Numbered claim (recommended for carousel slide 1, or as the A/B for the text post)
- **HE:** בתהליך AI יש רק שני מקומות למנהל.
  כל השאר זה שערים.
- **EN:** Two places a manager belongs in an AI flow.
  Everything else is a gate.
- Line 1: HE ~33 / EN 43 chars. Fits the carousel headline limit (≤50 HE / ≤60 EN).
- **Why #2:** The numbered/how-to archetype has the highest comment index (1.33), it states the whole thesis in two lines, and it is contrarian by implication ("only two"). The number is structural, so there is no fact risk. Risk: it is less personal (no I or scene), and engineers can read numbered posts as "framework content", so the body must stay practitioner-voiced.

### #3 First-person situation→twist (lowest-risk upgrade of the current hook)
- **HE:** אני רואה שוב ושוב את אותה הטמעת AI.
  התפוקה עולה, וההחלטות עדיין חוזרות למנהל.
- **EN:** I keep seeing the same AI rollout.
  Output goes up. The decisions still come back to the manager.
- Line 1: HE 35 / EN 34 chars, 7 to 8 words.
- **Why #3:** It keeps the current meaning and promise, but swaps "your" for "I" (first person adds about +19%) and moves the twist to line 2 so line 1 is one sentence. "I keep seeing" is an experience claim (voice), not a fact. Weaker than #1 because "AI rollout" is generic.

### #4 Series follow-up / story (conditional: ⟦ITAY_CONFIRM⟧)
- **HE:** התגובות לפוסט על Minions הפתיעו אותי.
  כמעט אף אחד לא התווכח על המודל. כולם דיברו על האמצע.
- **EN:** The comments on my Minions post surprised me.
  Almost nobody argued about the model. Everyone talked about the middle.
- **Why #4:** First-person, time-anchored story (top opener class). It pulls back the 20+ people who commented last time, and it is true to the visible thread (spec detail, shift-left, happy-case, deterministic tools). Conditions: Itay confirms it matches his reading. No numbers about the comments (that would be B-01). It must not quote or name commenters. Also, HE line 1 opens with Hebrew, but "Minions" mid-line is fine. It ranks below #1 to #3 because it depends on the reader having seen the earlier post.

### #5 Contrarian
- **HE:** עוד סוכנים לא יחזירו לכם את היומן.
  להזיז את הבדיקות כן.
- **EN:** More agents won't give you your calendar back.
  Moving the checks will.
- **Why #5:** A clear stance under 15 words with real tension (the pattern of the top exec posts), and it hits the ICP pain "no time for strategic work". It ranks lower because "calendar" shifts the focus from decision ownership to time, opens with "you", and the claim "moving the checks will" is close to a promised outcome. Soften in the body to "worth testing" so it doesn't edge toward B-07.

### #6 Personal story, time-anchored (conditional: ⟦ITAY_CONFIRM⟧)
- **HE:** בחודש שעבר הפסקתי לעבור על הטיוטות שלי באמצע.
  העברתי את עצמי להתחלה ולסוף.
- **EN:** Last month I stopped reviewing my own drafts halfway.
  I moved myself to the start and the end.
- **Why #6:** This is the strongest opener *class* by data (story anchored in time, plus first person), and it is honest only if it matches Itay's content-pipeline anecdote (already ⟦ITAY_CONFIRM⟧ in the core asset). It ranks low for **ICP fit**: it is a solo workflow, not a team or manager decision (ICP-1). It works better as a mid-post proof paragraph than as the hook.

### #7 Question (benchmark only; not recommended as the opener)
- **HE:** איפה יושב האדם בתהליך ה-AI של הצוות שלכם?
- **EN:** Where does the human sit in your team's AI flow?
- **Why last:** Question openers rank last in every 2026 dataset (−15% to −34%), and this one duplicates the CTA. Keep it as the **closing** line, where it already is.

## 4. Recommendation

**Switch.** Replace the text-post hook with **#1** in both languages. Keep the body and the CTA. Remove or reword the body line "The PR still waits for your 'one last look'" so it doesn't repeat the hook (e.g. "The design still waits for a sync you have to attend." can stay alone). Use **#2** as carousel slide 1, replacing "More AI output. Same decisions on your desk.", which is 2 sentences and generic. If Itay prefers a minimal change, use **#3**. Hold **#4** for the next post in the series, after confirmation.

Also, from the same data, at no cost: post with an image or carousel rather than text only (NBK: text-only scores 0.39 of the same author's image posts), no hashtags, and the Stripe link at the end of the text or in the first comment (no measurable difference). Plan 2 or 3 of Itay's own follow-up comments in the first hour, as in the Minions thread.

*Nothing was edited in the linkedin_text / carousel files. Itay decides (human gate).*

## 5. Sources (public, read 2026-11-03)

- NBK Social Research, *What Works on LinkedIn: 74,119 posts* (pub. 2026-10-09): https://www.nbksocial.com/research/what-works-on-linkedin/ (first line, opener, archetype, and close tables; within-author lens)
- AuthoredUp, *LinkedIn Hook Examples: What 310K Posts Reveal*: https://authoredup.com/blog/linkedin-hook-examples
- Flypost, LinkedIn study release (2026-10-13; 116k posts, within-creator; vendor, not peer-reviewed): https://www.flypost.io/press/linkedin-study-2026/flypost-linkedin-study-release-A.pdf
- MagicPost, *LinkedIn Hooks: What 1.2M Posts Say*: https://magicpost.in/blog/linkedin-hooks
- Executive Presence, *Executive LinkedIn Research: 6,035 posts*: https://executivepresence.io/executive-linkedin-research/
- Pinboostr, *LinkedIn Algorithm 2026: what LinkedIn has actually said* (dwell/skip, constructive-conversation signal): https://pinboostr.com/linkedin-algorithm/
- Social Media Today, LinkedIn stopped counting "see more" clicks: https://www.socialmediatoday.com/news/linkedin-shares-insights-into-latest-feed-algorithm-updates/708710/
- Liftli, "see more" fold (~140 mobile / ~210 desktop): https://liftli.ai/blog/linkedin-see-more-fold
- Klype, *LinkedIn posts for CTOs*: https://klype.ai/for/ctos.html · SocialNexis, *Content strategy for engineering leaders*: https://socialnexis.com/guides/linkedin-content-strategy-engineers
- Itay's Minions post (public page): https://www.linkedin.com/posts/itayfoyerstein_stripe-share-7518941479315070977-7PEg

**Caveats:** All of these datasets are correlational and come from vendors. None segments by EM/VP/CTO audience, and none covers Hebrew posts. Treat the rankings as priors and test them against Itay's own posts (one hook pattern per post, same day and time).
