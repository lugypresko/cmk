# Guardian self-check — run 001 · human-gates

Manual estimate against `guardian_rules.md` / `guardian_checklist.json` v1. **This is not a real Guardian run**: no DB, no scorer, `approved_facts` all still `draft`. Scores are best-effort estimates by the drafting agent. Every piece is `status: draft`, `approved_by: null`. **Nothing was published or scheduled.**

## Summary verdicts

| Piece | Variant | Blockers | brand (est.) | ICP (est.) | Expected verdict |
|---|---|---|---|---|---|
| core_asset_en | as written (Stripe ¶ + ITAY_CONFIRM ¶) | B-01 (Stripe) | ≤74 (capped; ~86 uncapped) | ~84 | needs_changes |
| core_asset_en | Stripe ¶ deleted, ITAY_CONFIRM resolved | none | ~84 | ~84 | pass → in_review |
| core_asset_he | as written | B-01 (Stripe) | ≤74 (~85 uncapped) | ~82 | needs_changes |
| core_asset_he | Stripe ¶ deleted | none | ~83 | ~82 | pass → in_review |
| linkedin_text_en | A (with ⟦STRIPE⟧) | B-01 | ≤74 (~87) | ~85 | needs_changes |
| linkedin_text_en | B (⟦STRIPE⟧ deleted) | none | ~84 | ~85 | pass → in_review |
| linkedin_text_he | A | B-01 | ≤74 (~86) | ~82 | needs_changes |
| linkedin_text_he | B | none | ~83 | ~82 | pass → in_review |
| carousel_en | slide 6 Stripe | B-01 | ≤74 (~84) | ~83 | needs_changes |
| carousel_en | slide 6 fallback | none | ~82 | ~83 | pass → in_review |
| carousel_he | slide 6 Stripe | B-01 | ≤74 (~83) | ~80 | needs_changes |
| carousel_he | slide 6 fallback | none | ~81 | ~80 | pass → in_review |

Thresholds: brand ≥ 75 and ICP ≥ 70, no blocker. **Once `proof.stripe_minions.pattern` is approved and added to `fact_ids`, Variant A of every piece should pass** with the higher (uncapped) score (BR-5 goes from 8 → ~13–15 with a sourced proof).

## Brand score breakdown (EN text post, Variant B; others within ±3)

| Check | Max | Est. | Note |
|---|---|---|---|
| BR-1 Evidence before diagnosis | 15 | 13 | Situation first ("output went up, decisions come back", PR waits for last look), then pattern. No "bottleneck" label anywhere. Evidence is experiential, not a specific anonymized case. |
| BR-2 System, not person | 10 | 10 | "Nobody moved the checks"; names where the human sits in the flow, not a manager flaw. |
| BR-3 Promise alignment | 15 | 14 | Closes with "needed at the right level"; "decisions still come back to you" in hook. |
| BR-4 Human at start and end | 10 | 10 | It is the thesis. |
| BR-5 Evidence + numbers, traceable | 15 | 8 | Concrete but number-free (rule: 8). Rises with approved Stripe proof. |
| BR-6 One reversible move | 10 | 10 | Rule-vs-judgment split of one recurring review. |
| BR-7 Practitioner tone | 10 | 9 | Calm, first person, no hype. |
| BR-8 CTA | 10 | 10 | Single situational binary question about the reader's team. |
| BR-9 Language craft | 5 | 4 | HE adapted (different hook rhythm, "← " bullets), not calqued; HE seeds still needs_review. |
| Penalties | | 0 | No avoid_phrases, hype, AI tells; 0 exclamation marks. |
| **Total** | 100 | **~84** | |

## ICP breakdown (EN text post)

| Check | Max | Est. | Note |
|---|---|---|---|
| ICP-1 Manager lens | 30 | 28 | "your team", "dev managers", "a review that keeps coming back to you". |
| ICP-2 Pain match | 25 | 25 | "Decision that comes back for one last check" + "meeting you have to attend" (AI-era form). |
| ICP-3 Leadership decision, not tooling | 20 | 16 | About where judgment sits; lints/tests are illustrative, not a tool tip. |
| ICP-4 Company context | 10 | 6 | Scaling R&D implied, B2B SaaS not explicit. |
| ICP-5 Secondary lens | 10 | 6 | CTO/VP R&D can map to org/pipeline design. |
| ICP-6 Engineer-readable | 5 | 5 | PR, lints, tests, CI-style language. |
| Penalties | | 0 | Not IC-only, not founder-only, no not_a_fit framing. |
| **Total** | 100 | **~86 → reported ~85** | |

## Mechanical checks (measured with a script on the files)

| Check | Result |
|---|---|
| B-11 / F-T2 length | text EN: A 1,591 / B 1,379 chars; text HE: A 1,276 / B 1,104 chars. All within 600–2,200, under 3,000. |
| F-T1 hook | EN first line 47 chars, HE 35 chars; hook = first two lines of body. |
| F-T4 / F-T5 / F-T6 | 0 hashtags, 0 links in body (Stripe URL is first-comment only), 0 emojis. |
| V-04 | 0 exclamation marks in any piece. |
| B-01 digits | No digits in any post/slide/caption text. |
| B-02 pricing regex | No hits (an early "מחיר" in core_asset_he was rewritten to avoid a false positive). |
| B-06 language | HE text post ≈99% Hebrew letters after tech allowlist; EN pieces contain zero Hebrew characters. |
| F-C1/F-C2 | Both carousels: 8 slides, n = 1..8. |
| F-C3 | Hook headline EN 44 chars (≤60), HE 42 chars (≤50). |
| F-C4 | All headlines ≤ 44 chars, all slide texts ≤ 153 chars. |
| F-C5 | Slide 8 = the CTA question (matches `cta`, phrasing of slide split across headline+text). |
| F-C6 | Caption EN 522, HE 377 chars (150–1,300). |
| F-C7 | No HE headline starts with an English token (HE slide 6 body starts "ב-Stripe", headline is Hebrew). |
| L-05 twins | Same claims both languages; only third-party claim is the Stripe pattern, present in both. |
| Core length | Body EN ~518 words; HE ~411 words (within 400–700). |

## Findings / warnings

1. **B-01 blocker (all Variant A pieces): Stripe Minions statement.** "Stripe has written about 'Minions'… a person writes the task, deterministic steps… a human reviews the pull request." Qualitative only, **no numbers used anywhere** (Stripe's published PR-volume figures were deliberately left out). Still a third-party claim → needs an approved `proof.*` fact.
2. **ITAY_CONFIRM (core assets only):** paragraph saying Itay runs his own content system this way (choose insight → automated checks → his approval). True to `agents.md`, but it's a first-person claim to the public; Itay decides whether to say it. Not used in posts/carousels.
3. **Core fallback paragraph** ("some engineering orgs… have published their setups") is still a generalization about third parties; safest is to delete the paragraph rather than use the fallback.
4. **Experience generalizations** ("I keep hearing this from dev managers", "in many teams") are unquantified → voice, not facts (C-05 not triggered). Itay should confirm they reflect his real conversations.
5. **"The WHAT lives in the message; the HOW lives in the system"** reuses the framing of the approved EN Minions exemplar. Intentional for continuity; flag if Itay wants a fresh line.
6. **HE gender (L-03):** reader address is plural throughout (אתם/אליכם, קחו, רשמו, סמנו). "המנהל" is used generically in third person (not an imperative) — minor; could become "המנהל/ת".
7. **Checker false-positive risk (tooling, not content):** `he_number_words` includes "אחד" and "פי". HE text contains "אף אחד" and words like "פיתוח"/"פייפליין". The scorer should use word boundaries and classify "אף אחד" as non-numeric; otherwise B-01 fires falsely.
8. **ICP-4 minor:** "B2B SaaS" is not explicit. Could add "in a growing SaaS team" if Itay wants ICP-4 full points; not needed to pass.
9. **Soft offer P.S.** ("Start with one real situation…") appears only in the core assets as optional, after the question (CTA-05 safe). Posts end on the question only.

## What Itay must approve (human gates)

1. **Core insight** — confirm this run's insight row (approved, confidentiality `public`).
2. **Fact `proof.stripe_minions.pattern`** (draft proposal below) — or choose Variant B / fallback slides everywhere.
3. **ITAY_CONFIRM** paragraph in the core assets — keep or delete.
4. **Core assets EN + HE** — approve after Guardian (first approval gate).
5. **Each of the 4 pieces** (text EN/HE, carousel EN/HE), Variant A or B — separate approvals.
6. **HE voice** — the HE seeds in `brand_voice`/`icp_profiles` are still `needs_review=true`; the HE copy here was scored by meaning.
7. Later gates (not reached): PackageBuilder preview (HE carousel RTL PDF), Scheduler slot, publish confirmation. Default distribution is manual.

### Proposed `approved_facts` row (status = draft, for Itay to approve)

```sql
INSERT INTO cmk.approved_facts (fact_key, category, statement_en, statement_he, source_url) VALUES
 ('proof.stripe_minions.pattern', 'proof',
  'Stripe has written publicly about "Minions", its in-house coding agents: a run starts from a task a person writes, interleaves agent loops with deterministic steps such as linters and tests, and ends in a pull request that a human reviews.',
  'ב-Stripe כתבו בפומבי על Minions, סוכני הקוד הפנימיים שלהם: ריצה מתחילה ממשימה שאדם כותב, משלבת לולאות של סוכן עם שלבים דטרמיניסטיים כמו לינטרים וטסטים, ונגמרת ב-PR שאדם עובר עליו.',
  'https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents');
-- status stays 'draft' (default) until Itay sets status='approved', confidentiality='public'.
-- Part 2 (blueprints = deterministic code + agent loops): https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2
-- Deliberately NOT proposed for use in this run: Stripe's PR-per-week volume figures (would need their own proof.* row each).
```

## Status

All six content files: `status: draft`, `created_by: agent`, `approved_by: null`. No DB writes, no publishing, no scheduling.
