# CMK Agent Roster (v0 active, v1 SPEC path below)

Scope v0: **LinkedIn only, `text_post` + `carousel`, HE/EN.** Every agent reads memory before it writes and writes through `contracts.md`.
Global rules: agents set `status` only to `draft`, `in_review`, or `needs_changes` (via Guardian). `approved_by` is always a human. No invented pricing, client names, testimonials, or numbers. **Human at the start (Itay picks the insight) and at the end (Itay approves, and confirms schedule/publish).**

| Agent | Role | Autonomy | Inputs | Outputs (contract / table) | May write | May NOT | Human gate |
|---|---|---|---|---|---|---|---|
| **Orchestrator** | Runs the pipeline: picks the next step, routes Guardian verdicts, loops revisions (max 3) | medium | Queue of `core_insights` (approved), row statuses, GuardianReports | Run plan / step log (JSON, not persisted in v0); status routing | `status` = `draft`/`in_review`/`needs_changes` only, per Guardian verdict | Approve, schedule, publish; skip Guardian; edit content text; relax thresholds or CHECKs | Itay picks which insight enters the pipeline. Stops and asks after revision 3 or `recommend_reject` |
| **ResearchAgent** | Gathers raw material: past posts, public third-party proofs (e.g. Stripe Minions source), patterns from Itay's voice notes | medium | Itay's notes and voice notes, public URLs, `past_content`, `performance_logs` | `core_insights` rows (draft); proposed `approved_facts` rows (draft, with `source_url`); `past_content` imports | `core_insights` (status=draft, created_by=agent); `approved_facts` (status=**draft** only); `past_content` (not `is_exemplar`/`is_anti_example`) | Approve facts or insights; mark exemplars; use `private` material; store client names; treat analytics viewer data as content | Itay approves facts, insights, and exemplar flags |
| **CoreCreator** | Turns one approved insight into one Core (thesis, body, key points, CTA) in the primary language | medium | Approved `core_insights` row, active `brand_voice`, target `icp_profiles`, approved+public `approved_facts`, exemplars | `cmk/CoreAsset` → `core_assets` (draft) + `content_fact_refs` | `core_assets` (draft, new rows/revisions), `content_fact_refs` (core) | Cite facts outside `fact_ids`; set scores; set approved; write channel pieces | Guardian, then Itay approves the Core |
| **Repurposer** | Multiplies an approved Core into a LinkedIn `text_post` and `carousel`, in EN and/or HE (adapted, not translated) | medium | Approved `core_assets`, active `format_specs` (text_post/carousel × he/en), exemplars, correction_log rules | `cmk/ContentPiece` → `content_library` (draft, `revision`, `parent_id`) + `content_fact_refs` | `content_library` (draft), `content_fact_refs` (piece) | Add claims not in the Core's `fact_ids`; add other formats/channels; overwrite a previous revision; edit an approved piece (a new revision is required) | Guardian, then Itay approves each piece |
| **BrandGuardian** | Gate: runs `guardian_rules.md` / `guardian_checklist.json` and scores brand + ICP | **split 2026-11-03 (D1):** SpecGate + FactGate (code, block) + EditorialGuardian (scores only); see Critique alignment. No approval rights | Piece or Core, active `brand_voice`, `icp_profiles`, `approved_facts`, `format_specs`, exemplars | `cmk/GuardianReport` on the row; `correction_log` rows for blocker/major findings | `brand_score`, `icp_relevance_score`, `guardian_report`, `guardian_checked_at`, `status`→`in_review`/`needs_changes`; `correction_log` (corrected_by=agent) | Rewrite content; approve; lower thresholds; use reach analytics to raise ICP score; promote rules into brand_voice/format_specs | Itay reviews every `in_review` item. Rule promotions (3+ repeats) need Itay |
| **PackageBuilder** | Builds the publish-ready package from an **approved** piece: final text, carousel PDF (RTL for HE), alt text, first-comment link | high (mechanical) | Approved `content_library` row | Package JSON `{content_id, revision, post_text, first_comment, carousel_pdf_path, alt_text[], checksum}` + files under `packages/<content_id>/r<revision>/` | Files only (no DB writes in v0) | Change wording, numbers, or CTA (any change means a new revision and another Guardian pass); package non-approved rows | Itay previews the package (rendered PDF) before scheduling |
| **Scheduler** | Proposes a slot (and later the 14-day `rotation_slot`). May propose the same approved revision again only when Itay marked it exact-repeatable | low | Approved + packaged pieces, exact-repeat rules, past `published_at`, `performance_logs` timing | ScheduleProposal JSON `{content_id, proposed_at (Asia/Jerusalem), rationale}` | Nothing on its own. It writes `scheduled_at` + `status='scheduled'` only to carry out Itay's explicit confirmation (confirmer logged). `repeats_done` increments only when a later appearance is confirmed live | Schedule unapproved rows; schedule more than 1 LinkedIn post/day; change content; verbatim-repeat a piece Itay did not mark exact-repeatable; schedule an exact repeat whose hash, asset checksums, or referenced facts are no longer valid | Itay confirms each slot |
| **Distributor** | Publishes to LinkedIn, or hands off for Itay to post manually (v0 default: manual) | low | Scheduled row + package | Publish record `{content_id, external_post_id, external_url, published_at}` | `external_post_id`, `external_url`, `published_at`, `status='published'`, only after the post is verifiably live and Itay has confirmed it | Post anything not `scheduled`; edit the post after publishing; comment/DM/reply as Itay; touch other channels | Itay confirms each publish (externally visible) |
| **Measurement** | Imports post analytics (e.g. LinkedIn xlsx export) and reports what's working | medium | LinkedIn exports, Itay's log of ICP conversations, time-saved estimates | `performance_logs` rows (source=`import`/`manual`); weekly insight note (topics, comment rate, ICP share of reach) | `performance_logs` | Change Guardian rules/thresholds or ICP definition; publish viewer/company data; invent `icp_conversations` or `time_saved_minutes` | Itay enters or confirms `icp_conversations` and `time_saved_minutes` (the two success metrics) |
| **ErrorWatcher** | Monitors Guardian failures, repeated `correction_log` patterns, Measurement anomalies; proposes Memory/rule promotions | medium | `correction_log`, GuardianReports, `performance_logs`, `agent_journal` | ProposedRule / Memory patch (draft); journal entries | `correction_log` (proposals), `agent_journal`, draft updates to brand_voice/format_specs as **new versions only** | Auto-promote rules; rewrite live content; approve; publish; lower thresholds | Itay approves every rule promotion and Memory version bump |

## v0 flow
```
Itay picks insight → ResearchAgent (facts as draft → Itay approves) → CoreCreator → BrandGuardian → Itay approves Core
→ Repurposer (text_post + carousel, he/en) → BrandGuardian → Itay approves pieces
→ PackageBuilder → Itay previews → Scheduler proposes → Itay confirms → Distributor (manual default) → Measurement → ErrorWatcher (weekly / on 3+ same correction)
```

## Open decision for Itay
`README.md` says agents only set `draft`/`in_review`. Scheduler and Distributor write `scheduled`/`published` **only as the execution of an explicit, logged human confirmation**. If you'd rather keep the rule literal, those two transitions become manual DB/UI actions and both agents only emit proposals.

---

## v1 (SPEC): what changes per agent

The v0 table above stays in force, and the v1 changes stack on top of it. A format joins an agent's scope only after a human sets `format_registry.v0_enabled = true` for it. Its `format_specs` rows have to be non-stub and active first. The trust rules don't change: humans approve, agents propose, and the Guardian gates.

| Agent | v1 change | New reads | New writes | Still may NOT |
|---|---|---|---|---|
| **Orchestrator** | Routes every enabled format. Runs a per-format Repurposer→Guardian loop (max 3 revisions each). Sets `cmk.actor_*` / `cmk.run_id` session context on every write | `format_registry`, `prompt_versions` (active) | none new (audit rows come from triggers) | Enable formats, activate prompts, change thresholds |
| **ResearchAgent** | Proposes topic queue changes from `measurement_reviews` | `measurement_reviews` (approved) | `core_insights` (draft) | Approve facts; create the avatar consent fact |
| **CoreCreator** | Records `prompt_version_id` on each Core | `prompt_versions` | `core_assets.prompt_version_id` | as v0 |
| **Repurposer** | Produces all enabled formats from one approved Core: fills `payload` per `contracts.md` v1, `media_refs` as **briefs** (no rendering) | `format_specs` (11 formats), `format_registry` | `content_library.payload`, `media_refs`, `prompt_version_id` | Produce a disabled format; add claims outside `fact_ids`; write avatar pieces without a resolvable `consent_ref` |
| **MediaProducer** *(proposed, not from the SPEC text)* | Renders images and video from `media_refs` briefs: carousel/infographic images, b-roll, reel/short edits, avatar video | approved pieces, brand assets | files under `packages/<id>/r<rev>/media/`; fills `media_refs[].path` | Change text, numbers or on-screen copy (any change makes a new revision); use people's likeness without consent; use unlicensed media |
| **BrandGuardian** | Format checks for 9 new formats (beats contiguous F-V1, poll limits, alt text, AI disclosure, consent B-13); scans every `payload` text field; reports `score_scale`, float mirrors, `threshold_profile` | `guardian_thresholds` (active), `format_specs` new columns | `guardian_threshold_profile` | Switch the threshold profile; score from reach |
| **PackageBuilder** | Packages per format: thread text file, video + SRT, poll spec, story frames, email HTML/plain | approved pieces + media | files only | as v0 |
| **Scheduler** | Builds the 14-day plan (`scheduler_14day.md`), proposes per slot (v0) or per plan (later). Exact repeats reuse the approved `content_id`; other refreshes stay on the new-revision path | `rotation_plans`, `rotation_slots`, `performance_logs` windows, exact-repeat columns | `rotation_plans`/`rotation_slots` (draft/proposed/filled); `scheduled` only on a logged human confirmation | Exceed `daily_caps`; schedule unapproved or disabled formats; verbatim-repeat a piece that is not an approved exact repeat; schedule an exact repeat after the approved hash, asset checksums, or referenced facts are no longer valid; auto-publish |
| **Distributor** | One adapter per channel (LinkedIn, X, IG/FB, YouTube, email). Manual hand-off stays the default until each adapter is approved | confirmed slots + packages | publish records | Post to a channel whose adapter Itay didn't approve; send email to non-opted-in lists |
| **Measurement** | Capture windows 24h/72h/7d/14d/lifetime, per-format metrics, weekly `measurement_reviews` (`measurement_loop.md`) | all `performance_logs` | `performance_logs`, `measurement_reviews` (draft) | Approve its own proposals; invent `icp_conversations` / `time_saved_minutes` |

### Human gates added in v1
1. **Enable a format**: Itay reviews its stub `format_specs` and sets `is_stub=false`, then `is_active=true`, then `format_registry.v0_enabled=true`.
2. **Activate a prompt**: the `prompt_versions` status goes to `approved` and `is_active`, set by a human.
3. **Threshold profile switch** (`guardian_thresholds.md`).
4. **Rotation plan / slot confirmation** (`scheduler_14day.md`).
5. **Avatar consent**: Itay himself creates an approved `boundary.*` fact recording consent for his likeness and voice. No avatar piece passes without it.
6. **Measurement proposals**: Itay accepts or rejects each one.
7. **Channel adapters**: each auto-posting integration gets approved once, per channel.

### Critique alignment (ACCEPTED 2026-11-03)
Itay locked D1–D5 on 2026-11-03 (`ARCHITECTURE_CRITIQUE_RESPONSE.md` → *Decisions locked*). Schema draft: `migrations/005_critique_alignment.sql` (**not applied yet**). Where this section conflicts with the v0/v1 tables above, **this section wins**. Trust rules are unchanged: humans approve, agents propose, code gates block.

**Code vs. agents**
| Step | Implementation | Owner in `work_items.owner` |
|---|---|---|
| Orchestrator | **code**: state machine over `work_items`/`work_transitions` (one row per derivative; owner, attempt_count/max_attempts, blocked_on, stop_reason, lease). A failed carousel never blocks a valid text_post. No Temporal or other engine | `Orchestrator` |
| ResearchAgent, CoreCreator, Repurposer | **agents** (judgment) | role name |
| SpecGate, FactGate | **code** (FactGate uses a narrow LLM call only to extract claim candidates; matching is code) | `SpecGate` / `FactGate` |
| EditorialGuardian | **agent** (LLM judge, scores only) | `EditorialGuardian` |
| MediaProducer | code/tool pipeline from templates (LLM only to draft briefs) | `MediaProducer` |
| RenderQA, PackageBuilder, Scheduler, Distributor | **code** | role name |
| Measurement | **code** for import/aggregation; LLM only drafts the weekly note from computed numbers | `Measurement` |
| ErrorWatcher | **code** detection/classification/replay + LLM proposal text | `ErrorWatcher` |
| Human gates | Itay | `Itay` |

**Guardian = deterministic Spec+Fact gates + editorial review (D1)**
| Gate | Kind | Owns (existing check ids) | Can block? |
|---|---|---|---|
| **SpecGate** | code | S-01, B-11, F-*, `payload_ok()`, B-06 language, B-02/B-07 token patterns, B-09, B-13/B-14 (record exists), AI-disclosure flag on generated media | **yes** |
| **FactGate** | code | §6 claim → `fact_id` in `usable_facts_v` (approved + public + not expired), numbers ≤ fact, B-01, B-08, L-05, C-04 | **yes** |
| **EditorialGuardian** | LLM | brand §2, ICP §3, CTA §8, B-05 pinning judgment, "does the source support this wording", "does the derivative add value or mislead" | **no.** It scores and flags. It can never turn a SpecGate or FactGate block into a pass. It may set `recommend_reject` |
- Gate 1 (Core): FactGate + EditorialGuardian on the core claims, then Itay. Gate 2 (each derivative): SpecGate + FactGate + EditorialGuardian, then RenderQA on its file, then Itay.
- None of the three writes `approved*`. Thresholds stay as the active profile (v0 75/70) and apply to the editorial scores.

**Approvals and edits (D2: audit-only)**
- The schema does **not** freeze approved rows or revoke approval on edit. The DB records `approved_content_hash` at approval. A later change sets `edited_after_approval` and writes an audit row.
- **Process rule for agents (guidance, not enforced):** never edit an approved/scheduled piece. Make a new revision (`parent_id`, `revision+1`) and run the gates again. If an edit happens anyway, the Distributor shows Itay the `edited_after_approval` flag and the hash mismatch at publish confirmation.
- Accepted risk: an approval can survive an edit. An exact repeat does not close that gap with a freeze. The scheduler refuses the repeat when the live hash or asset checksums differ from the hashes Itay stored on the rule, and the approval stays in place.

**MediaProducer → RenderQA → PackageBuilder**
- MediaProducer renders from an approved revision + `media_refs` briefs. Each file becomes a `media_assets` row (storage_uri, sha256, dims/duration/page_count, source, license_note, consent_fact_id, ai_disclosure). It never changes text, numbers or on-screen copy.
- **RenderQA (code)** runs on every file: it opens; slide/page count = `slides`; within `format_specs`; extracted or OCR text = the approved text; HE is RTL; alt text present; subtitles for video; stock needs a license note; generated needs a disclosure. Result: `qa_status` + `qa_report`. A fail → `work_items` `needs_changes` for that derivative only.
- PackageBuilder only packages `qa_status='pass'` assets. Itay previews the rendered file. **This applies now to the v0 carousel PDF.**

**Distributor (D3: unknown → escalate, never auto-resend)**
- Every publish = one `publish_instances` row (content revision, `sent_content_hash`, account_ref, slot). Every try = one `publish_attempts` row with a unique id, which is also used as the provider idempotency key where one is supported.
- `timeout`/`unknown` outcome → instance `unknown` + `escalated_at` → Itay. The DB refuses another attempt. Only a human moves it out of `unknown` (confirmed / cancelled / failed_final / explicit re-queue).
- A known transient error (`rate_limit`/`provider_5xx`/`network`) → `failed_retryable` → retry up to `max_attempts` (default 2). Any other error → `failed_final` + escalate.
- `confirmed` needs an external id/url + confirmer. Manual v0 posting uses the same rows, with Itay as the confirmer. DB uniqueness prevents local duplicates only.

**Measurement → lead_threads handoff (D5)**
- Measurement suggests ICP-conversation candidates as `lead_threads` rows with `stage='suggested'` (conversation_ref, source content, channel). Itay confirms (stage → `new`, `confirmed_by`).
- Itay is the default owner. Stage, owner, confirmation, `proposal_*` and `payment_status` are **human-only** (DB trigger). Agents read only `lead_handoff_v` (no proposal or payment columns). No amounts or prices are stored. Content agents never use lead data in content (B-12).
- No new agent. Lead follow-up stays with Itay.

**ErrorWatcher (D4: memory stays in Postgres rows)**
- event → classify into `correction_log.memory_kind` ∈ {content_error, preference_once, policy_gap, fact_change, hypothesis, infra_failure} → propose a new version (`brand_voice` / `format_specs` / `prompt_versions` / `approved_facts`) → **replay** on past approved pieces + anti-examples (`replay_report`) → Itay approves → new version.
- Only `policy_gap` and `fact_change` can be promoted, and only with a `rule_reason` + `replay_report` (DB CHECK). `content_error` fixes one piece. `preference_once` is never promoted. A reach drop is a `hypothesis`. `infra_failure` is an ops item.

**Volume and schedule**
- "~100/day" = mainly **publish instances** via reuse + rotation (`volume_daily_v`). New families, new derivatives and the approval queue (`approval_queue_v`) are counted separately.
- `rotation_slots` is the schedule authority. Google Calendar is a one-way view. Quiet days stay a manual `quiet_days` list. Hebrew holidays are not added automatically.
- **Exact repeat (locked 2026-11-03 20:35 Asia/Jerusalem).** A LinkedIn `text_post` or `carousel` Itay marks `is_exact_repeatable` can be proposed again every `repeat_every_days` (default 14) until `repeat_until` or `max_repeats`, using the same `content_id` and revision. He sets both limits when he marks it. The 4-day same-core spacing and the "already in an open plan" exclusion do not apply to that slot. The scheduler still refuses it when `edited_after_approval` is set, the live hash or asset checksums differ from `repeat_approved_content_hash` / `repeat_asset_hashes`, or a referenced fact is expired or retired. That refusal does not revoke approval (D2). Each repeat is a new `publish_instance` with the same `sent_content_hash`.
- **New revision.** A non-repeatable evergreen refresh, or any refresh after the facts change, is still a new `content_library` row through Repurposer, Guardian, and approval. The scheduler lists those pieces and does not verbatim-fill them.

---

## Agent journal (mandatory)
- **Every agent MUST append a journal entry after each meaningful action**: a file in `journal/entries/` plus a row in `cmk.agent_journal` (`migrations/004_agent_journal.sql`). Fields: `id, ts, agent, workflow (A|B|C|ops), action, inputs, outputs, status, human_gate, notes`.
- The journal is append-only. A correction goes in a new entry that references the old `id`.
- **The Orchestrator reads the last N entries (default N=20) before planning**, and checks open `human_gate`s first.
- See `journal/AGENT_JOURNAL.md`.


## Implemented focused research runtime (2026-11-04)

The ResearchAgent responsibility is implemented as TopicResearchAgent → HookResearchAgent →
ResearchSynthesisAgent, each with its own prompt and durable research_agent_tasks row. They operate
inside CMK and pass source-referenced outputs to the next role. ResearchSynthesisAgent proposes one
insight; CoreCreator and Repurposer proceed only after the existing human gates. Source collection,
evidence validation and SpecGate/FactGate remain code per D1. EditorialGuardian is currently a
heuristic stub, not an implemented LLM judge; human editorial review remains necessary.
See [docs/RESEARCH_RUNTIME.md](docs/RESEARCH_RUNTIME.md). No role approves content or facts.
