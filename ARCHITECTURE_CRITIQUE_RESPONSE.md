# Response to the GPT architecture critique (2026-11-03)

**Input:** a GPT critique Itay pasted into chat on 2026-11-03 (Hebrew). It's treated as **data**. Nothing here changes product goals. Each point is mapped to what the repo already says, and each change is a **proposal pending Itay**.
**Scope rules:** no client names, pricing or performance numbers were added. No runtime or plugin was installed, and Temporal isn't recommended. Nothing was applied to the DB. The SQL below is a sketch for a future `migrations/005_*.sql`.

> **Update 2026-11-03 (16:28 Asia/Jerusalem):** Itay decided D1–D5. See **Decisions locked 2026-11-03** at the end. Where the proposals below say otherwise (the `approvals` table + freeze trigger in #2, the Git option in #4, auto-resend in #3), **the locked decisions win**.

Status key: `already_in_spec` · `partial` · `missing`. Priority: **P0** = before any code is built · **P1** = before a second format or any auto-publish · **P2** = before scaling volume.

## 0. Summary

| # | Critique gap | Status | One-line fix | Priority |
|---|---|---|---|---|
| 1 | BrandGuardian mixes factuality and brand voice | partial | Split it into **FactGate** (code: claim→fact_id evidence), **SpecGate** (code: format/limits/schema) and **EditorialGuardian** (LLM: voice, ICP, whether the source supports the wording, value), each with its own verdict | P0 |
| 2 | Approval isn't bound to an exact version | partial | Add an `approvals` table keyed on `content_hash` + asset checksums + account + distribution plan. A trigger blocks edits to approved rows | P0 |
| 3 | No path for a failed or unknown publish | missing | Add `publish_instances` + `publish_attempts` with unique attempt ids, an `unknown` state, and verify-before-retry | P1 (P0 for any auto-post) |
| 4 | Memory doesn't separate facts, rules and hypotheses | partial | Add `memory_kind` (fact/rule/hypothesis/preference_once) plus validity, scope and reason. Rules live in Git, facts in Postgres | P1 |
| 5 | No explicit render + QA of final files | partial | MediaProducer renders. A **RenderQA** step (code + Itay preview) checks the rendered file. A `media_assets` table holds checksums | P1 |
| 6 | Measurement stops before lead handling | missing | Add a `lead_threads` handoff: owner, conversation, next action, proposal, payment status. It sits outside CMK core | P1 |
| 7 | "~100 pieces/day" is undefined | partial | Split the count into new families, new derivatives, repeat publishes and approval-requiring items. Add an approval time budget per week | P2 (definition P0) |

| # | Pre-build change | Status | One-line fix | Priority |
|---|---|---|---|---|
| A | Orchestrator as a DB-persisted state machine | missing | Add a `work_items` table, one row per derivative: state, owner, attempt_count, max_attempts, stop_reason. Plain Postgres, no workflow engine | P0 |
| B | Sharpen the two gates + version-bound approval | partial | Gate 1 = Core claims + edit. Gate 2 = each derivative **and its rendered file**. Approvals carry a hash (= #1 + #2 + #5) | P0 |
| C | Explicit publish/confirm model with unique ids | missing | Same as #3. Note: DB uniqueness only prevents **local** duplicates. The provider has to be queried before any retry | P1 |
| D | ErrorWatcher limited to tested, approved proposals | partial | Path: event → classify (content / policy / infra) → propose → replay on past examples → Itay approves → new version | P1 |
| E | Business outcome + capacity in planning; avatar/disclosure as explicit expansion requirements | partial | Lead owner + next action (= #6), weekly approval budget (= #7). Avatar and disclosure stay Phase 3 gates (already there) | P1 |

**Already covered (keep):** versioned memory, with `prompt_versions` immutable and one active per key. The DB refuses `approved/scheduled/published` without human `approved_by`. ErrorWatcher only proposes. Two formats ship first. Volume is a cap, not a goal. Recycling makes a new revision, re-run through Guardian and approval. Avatar needs a consent fact and the B-13 disclosure check. Measurement never feeds Guardian scores, and small n is treated as a hypothesis.
**Truly missing:** publish attempts and unknown outcomes. Approval bound to a content hash (a trigger that freezes approved rows). A persisted per-derivative work state. Lead handling after a conversation. A definition of what "100" counts. A rendered-file QA step. The memory kind/scope/validity split.

---

## 1. Gap 1: BrandGuardian mixes factuality and brand voice (Critical)
**Status: partial.**
- Already there: `guardian_rules.md` §0 orders the checks (schema → blockers → format → language → claims → confidentiality → CTA → score). §6 already separates claims into fact, experience and opinion, and B-01 blocks any unsourced fact. `brand_score` and `icp_relevance_score` are separate.
- Gaps: it's one agent with one verdict and one `GuardianReport`. `agents.md` calls it a "deterministic gate", but §2/§3 (voice, ICP) and §6 step 2 (classifying claims) are **semantic**. The critique is right that a hard gate can show evidence is **missing**. It can't prove a claim is **true**, or that the source supports the wording.

**Proposed change**
| Gate | Kind | Checks (existing ids) | Verdict |
|---|---|---|---|
| **SpecGate** | code, deterministic | S-01 schema, B-11, F-* format checks, `payload_ok()`, language detection (B-06), banned tokens for pricing (B-02 patterns) and guarantees (B-07), B-09 gate bypass, B-13/B-14 (consent/opt-in **record exists**) | pass / block |
| **FactGate** | code + narrow LLM extraction | claim extraction (§6.1). Every fact-claim maps to an approved+public `fact_id` (B-01, B-08). Numbers ≤ the fact (§6.3). Twin parity L-05. C-04 | pass / block + `unsupported_claims` |
| **EditorialGuardian** | LLM judgment, advisory score | brand §2, ICP §3, CTA §8, confidentiality judgment (B-05 pinning), **"does the source actually support this wording"**, "does the derivative add value or mislead" | score + findings. It **never** turns a block into a pass |

- Contract: `GuardianReport` v2 = `{spec: {...}, fact: {...}, editorial: {...}, verdict}`. Verdict = block if SpecGate or FactGate blocks. Otherwise the thresholds apply to the editorial scores.
- Wording fix: rename "deterministic Guardian gates" in `agents.md`/`README.md` to "deterministic **evidence and spec** gates + editorial review". A deterministic claim of truth is never made.
- Itay decision: none needed for the split itself (it's a refactor of existing rules). See D1 for whether EditorialGuardian may also emit `recommend_reject`.

## 2. Gap 2: Approval isn't bound to an exact version (Critical)
**Status: partial.**
- Already there: `content_library.approved_by/approved_at`, enforced by CHECK (schema.sql, content_library). `revision` + `parent_id`. "Edit an approved piece → a new revision is required" (agents.md, Repurposer/PackageBuilder). `audit_log` records `body`/`payload` changes (002 §7). The PackageBuilder package carries a `checksum`. `prompt_versions` is immutable (002 §3).
- Gaps: **no trigger stops an UPDATE of `body/slides/payload/media_refs` on an approved row**. The approval would silently survive the edit, because the audit log records it but doesn't block it. Approval doesn't name the rendered assets, the account (e.g. which LinkedIn profile or page), or the distribution plan (which slot or plan). The rotation-plan approval does say "a slot that changes after approval → `filled`" (scheduler_14day.md), and that's the right pattern, but only for slots.

**Proposed change (005 sketch)**
```sql
CREATE TABLE approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type text NOT NULL CHECK (subject_type IN ('core_asset','content_piece','rotation_plan','rotation_slot','memory_change')),
  subject_id uuid NOT NULL,
  content_hash text NOT NULL,          -- sha256 of canonical JSON (body, slides, payload, cta, hashtags, fact_ids)
  asset_hashes text[] NOT NULL DEFAULT '{}', -- sha256 of every rendered file (media_assets.sha256)
  account_ref text,                    -- target account/page id; NULL only for core_asset/memory_change
  distribution_ref uuid,               -- rotation_slot_id or plan id
  approved_by text NOT NULL, approved_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz, revoke_reason text,
  UNIQUE (subject_type, subject_id, content_hash, distribution_ref)
);
-- trigger: on content_library UPDATE of body/slides/payload/media_refs/cta/hashtags when status IN ('approved','scheduled')
--   -> RAISE EXCEPTION (edit = new revision) ; published rows fully immutable
-- trigger: publish requires an unrevoked approvals row whose content_hash = current hash AND asset_hashes = current media_assets
```
- Itay decision: **D2**.

## 3. Gap 3: No path for a failed or unknown publish (High)
**Status: missing.**
- Already there: Distributor writes `external_post_id/url/published_at` "only after the post is verifiably live and Itay has confirmed it" (agents.md). There's a unique index on `(channel, external_post_id)` (schema.sql). Manual distribution is the v0 default (SPEC_GAP F.4). Zernio is connected (journal 009), but no adapter is approved.
- Gaps: no attempt record, no `unknown` state (a timeout after sending), no retry limit, and no rule to check before resending. The external id unique index only works **after** an id is known. It can't stop a double post when the first response was lost.

**Proposed change (005 sketch)**
```sql
CREATE TYPE publish_state AS ENUM ('queued','sending','confirmed','failed_retryable','failed_final','unknown','cancelled');
CREATE TABLE publish_instances (            -- one intended appearance of one approved revision on one account at one slot
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id uuid NOT NULL REFERENCES content_library(id),
  approval_id uuid NOT NULL REFERENCES approvals(id),
  rotation_slot_id uuid, channel channel_code NOT NULL, account_ref text NOT NULL,
  state publish_state NOT NULL DEFAULT 'queued',
  external_post_id text, external_url text, confirmed_at timestamptz,
  max_attempts smallint NOT NULL DEFAULT 2, stop_reason text,
  UNIQUE (content_id, account_ref, rotation_slot_id),
  UNIQUE (channel, external_post_id)
);
CREATE TABLE publish_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),        -- also sent as the provider idempotency key where supported
  publish_instance_id uuid NOT NULL REFERENCES publish_instances(id),
  attempt_no smallint NOT NULL, started_at timestamptz NOT NULL DEFAULT now(),
  outcome text CHECK (outcome IN ('ok','error','timeout','unknown')), provider_response jsonb, error_class text,
  verified_via text,                                     -- 'provider_lookup' | 'itay_manual' | null
  UNIQUE (publish_instance_id, attempt_no)
);
-- at most one attempt in flight per instance: partial unique index WHERE outcome IS NULL
```
- Rules: `timeout` or `unknown` moves the instance to `unknown`. **No retry until there's a provider lookup** (list recent posts on that account and match on content hash or text prefix) or Itay confirms manually. `failed_final` and `unknown` past N hours go to Itay, and nothing is resent automatically. The manual v0 flow uses the same rows, with Itay as the confirmer. A failed carousel instance doesn't block a valid text instance (see A).
- Note from the critique, kept: local constraints **do not prove** what happened at the provider.
- Itay decision: **D3** (whether `unknown` is ever auto-retried after a provider lookup comes back negative, or always escalated).

## 4. Gap 4: Memory doesn't separate facts, rules and hypotheses (High)
**Status: partial.**
- Already there: `approved_facts` has `source_url/source_note`, `status`, approval, `review_by` and `confidentiality`. Rules are versioned in `brand_voice`, `format_specs` and `prompt_versions`. `correction_log.rule_candidate`, with promotion after 3+ repeats and Itay approval. `measurement_loop.md` §6 treats one post as a hypothesis.
- Gaps: no `valid_until` / `last_verified_at` on facts (only `review_by`). Rules carry no **reason**, and no **scope** (which accounts, formats or languages). Nothing stores a hypothesis as distinct from a rule. A one-off edit ("make this post shorter") has no `preference_once` type, so 3 similar one-offs could be promoted as a general rule. Rules, templates and prompts live in Postgres, not Git.

**Proposed change**
- `approved_facts` + `last_verified_at`, `valid_until`, `usage_scope text[]` (e.g. `{public_posts}`), `version`. The FactGate blocks expired facts the same way as B-08.
- New `memory_changes` table: `{id, kind: fact|rule|hypothesis|preference_once, target_table, target_key, from_version, to_version, reason, scope {channels, formats, languages, accounts}, evidence_refs[], test_run_id, approved_by, approved_at}`. `preference_once` is **never** promotable. A `hypothesis` needs an explicit Itay upgrade to become a `rule`.
- Storage split (critique point, **choose in D4**): rules, templates, prompts and the Guardian checklist live in **Git** (PR = proposal, CI = replay test, merge = approval), with Postgres holding the active git sha per key. Or keep them in Postgres as today (`prompt_versions` is already immutable and approval-gated). Facts, approvals, artifacts and work state stay in Postgres either way. Media files go to object storage, with refs from `media_assets` (see #5).

## 5. Gap 5: No explicit render + QA of final files (High)
**Status: partial.**
- Already there: MediaProducer is *proposed* (agents.md v1, "not from the SPEC text"). PackageBuilder makes the carousel PDF (RTL for HE), and "Itay previews the package (rendered PDF) before scheduling" (agents.md v0). `media_refs` includes alt_text, source and license_note. The `media_assets` table is an open gap (SPEC_GAP D, G.9).
- Gaps: no automated QA of the rendered file, no checksum tied to approval, no table.

**Proposed change**
- `media_assets {id, content_id, revision, kind, storage_uri, sha256, width, height, duration_s, page_count, source, license_note, consent_fact_id, render_job_id, qa_status, qa_report jsonb}`.
- **RenderQA** (code): file opens. Page or slide count equals `slides`. Dimensions and duration are within `format_specs`. On-screen text OCR or extracted text equals the approved text (no drift). HE renders RTL. Fonts are embedded. Alt text is present. Subtitles exist for video. Any mismatch blocks.
- Then Itay previews the **rendered file**. The approval's `asset_hashes` must match (= #2).
- v0 relevance: the carousel is a v0 format, so this applies **now** to the carousel PDF, not only to video.

## 6. Gap 6: Measurement stops before lead handling (High)
**Status: missing.**
- Already there: `icp_conversations` is human-confirmed (measurement_loop.md §3). `leads/` is internal ICP research. The offer is coaching that starts with one real situation (README).
- Gaps: once a conversation exists, nothing tracks who owns it, the next action, whether a proposal was sent, or payment. Engagement can grow with no paid engagement following.

**Proposed change**
- `lead_threads {id, source_content_id, source_publish_instance_id, channel, first_contact_at, owner (default 'Itay'), stage: new|replied|call_booked|proposal_sent|won|lost|nurture, next_action, next_action_due, proposal_ref, payment_status: none|pending|paid, notes, confidentiality}`. Content agents **never** read it. It holds no viewer analytics (B-12 still applies).
- Measurement only creates `suggested` lead rows. Itay confirms. Measurement then reports content → conversation → stage counts, with no invented values.
- Itay decision: **D5** (inside CMK as a small table, or handed off to an external CRM).

## 7. Gap 7: "~100 pieces/day" is undefined (Medium)
**Status: partial.**
- Already there: SPEC.md §1 "~100 content pieces published per day via REUSE + 14-day rotation". scheduler_14day.md: "Volume is a cap, not a goal", v0 `{"linkedin":1}`. rotation_plan_001 shows 100/day only as a target map.
- Gaps: no definition of what gets counted, and no approval-capacity model.

**Proposed change**
- Four separate counters per day and per week: `new_families` (new Cores), `new_derivatives` (new pieces needing Guardian + approval), `repeat_publishes` (publish_instances of already-approved revisions), `approval_items` (items waiting on Itay).
- `rotation_plans.constraints.approval_budget_minutes_per_week`. Itay sets the value; none is assumed here. The Scheduler can't propose a plan whose new approval items exceed the budget, based on Itay's measured review minutes from `audit_log` (no estimate invented).
- The ~100 target gets restated as `publish_instances/day` (whether that's right is a decision; see D5 note).
- **Repeat-every-14-days** (critique point): this repo says recycling is a new revision, never verbatim (scheduler_14day.md). The critique says an exact repeat can be fine if each repeat has a repeat count or end date, a fact-validity check, and a stop when a fact changes. That's a conflict with the current rule, so Itay decides (see D-extra in SPEC_GAP).

---

## A. Orchestrator as a DB-persisted state machine
**Status: missing.** agents.md: Orchestrator "Run plan / step log (JSON, **not persisted** in v0)". There's a revision max of 3, and it stops and asks after revision 3. `agent_journal` is a log, not state.
**Proposed (plain Postgres; no Temporal or other engine):**
```sql
CREATE TABLE work_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('core','derivative','render','package','publish','measure')),
  subject_id uuid, parent_work_item_id uuid REFERENCES work_items(id),
  state text NOT NULL,                 -- per-kind allowed transitions in work_transitions
  owner text NOT NULL,                 -- agent role or 'Itay'
  attempt_count smallint NOT NULL DEFAULT 0, max_attempts smallint NOT NULL DEFAULT 3,
  stop_reason text, blocked_on text,   -- e.g. 'human_gate:approve_piece'
  lease_until timestamptz,             -- one runner at a time; crash => lease expires => resumable
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE work_transitions (kind text, from_state text, to_state text, actor_type actor_type, PRIMARY KEY (kind, from_state, to_state));
-- trigger: reject transitions not in work_transitions; reject agent actor on human-only transitions
```
- Each derivative gets its own row, so a failed carousel doesn't block a valid text_post.
- Itay decision: none (it's an internal design choice). Flag it if he'd rather not add a table before v0 code exists.

## B. Sharpen the two gates, approval bound to the exact version
**Status: partial.** Gate 1 (Core → Guardian → Itay) and Gate 2 (each piece → Guardian → Itay) exist (agents.md v0 flow). Missing pieces: Gate 2 doesn't cover the **rendered file**, and approval isn't hash-bound.
**Proposed:** Gate 1 = FactGate + EditorialGuardian on the Core's core claims, then Itay approves the Core hash. Gate 2 = SpecGate + FactGate + EditorialGuardian on each derivative, then RenderQA on its file, then Itay approves the hash + asset_hashes. Covered by #1, #2 and #5.

## C. Explicit publish/confirm model
**Status: missing.** Same as #3. Priority P1. It becomes P0 the day any adapter (Zernio or native) is approved to auto-post.

## D. ErrorWatcher limited to tested, approved proposals
**Status: partial.** agents.md ErrorWatcher: proposes only, new versions only, Itay approves. Missing: the classification, and replay testing on past examples.
**Proposed path:** `event → classify {content_error (one piece), policy_gap (rule/voice/spec), fact_change, infra_failure (publish/render/import)} → propose → replay` the proposed rule or prompt version against the last N approved pieces and known anti-examples (does it flip previously approved items? does it catch the event?) `→ Itay approves → new version`.
- `content_error` → fix that piece only (new revision). It never becomes a rule.
- `preference_once` → logged, never promoted. Example from the critique: "make this post shorter" ≠ "always short".
- A reach drop → `hypothesis` only. It's never concluded automatically that "the opener failed".
- `infra_failure` → an ops ticket in the journal. **Never** a memory change.
- `fact_change` → retire or version the fact, then pull every scheduled piece that cites it (scheduler_14day.md re-planning already covers the pull).

## E. Business outcome + capacity in planning; expansion requirements
**Status: partial.** Covered by #6 and #7. Avatar and disclosure: already explicit Phase 3 requirements (README Phase 3 item 13, agents.md human gate 5, guardian_rules §11 B-13). Keep them, and add `disclosure_label_required` to the avatar/generated-media `format_specs` and the SpecGate.

---

## Which roles stay agents, and which become code
| Role | Recommendation | Why |
|---|---|---|
| ResearchAgent | agent | judgment on sources |
| CoreCreator | agent | writing |
| Repurposer | agent | adaptation judgment |
| EditorialGuardian | agent (LLM judge) | semantic |
| FactGate / SpecGate | **code** (narrow LLM only for claim extraction) | evidence/spec checks |
| Orchestrator | **code** (state machine over `work_items`) | routing, retries, leases |
| MediaProducer | code / tool pipeline (templates), with an LLM only for briefs | rendering is mechanical |
| RenderQA | **code** + Itay preview | file checks |
| PackageBuilder | **code** | mechanical |
| Scheduler | **code** (the algorithm in scheduler_14day.md is already deterministic) | constraint fill |
| Distributor | **code** (adapters + attempts) | idempotency |
| Measurement | **code** for import/aggregate; LLM only to draft the weekly note | numbers |
| ErrorWatcher | code for detection/classification rules + LLM for proposal text; replay is code | proposals |

## Calendar: one schedule authority
**Status: partial.** `rotation_slots` is the schedule (scheduler_14day.md). But run 001 also wrote 29 Google Calendar events (rotation_plan_001.md). **Proposed:** `rotation_slots` and `publish_instances` are the single authority. Google Calendar is a one-way **view** regenerated from them, and an edit made in the calendar is never read back as a schedule change.

---

## Decisions for Itay (max 5)
- **D1.** Split BrandGuardian into FactGate + SpecGate (code, can block) and EditorialGuardian (LLM, scores only, can't override a block)? **yes / no**
- **D2.** Freeze approved content: any edit to an approved or scheduled piece (text, slides, files, target account or slot) cancels the approval and needs re-approval of the new version? **yes / no**
- **D3.** An unknown publish outcome: **A** = always escalate to you, never auto-resend · **B** = auto-resend once only if a provider lookup proves the post isn't live
- **D4.** Rules, templates and prompts: **A** = move to Git (PR = proposal, merge = approval) · **B** = keep in Postgres `prompt_versions` as today
- **D5.** Lead handling after an ICP conversation: **A** = a small `lead_threads` table inside CMK (owner, next action, proposal, payment) · **B** = hand off to an external CRM, with CMK storing only a link

(Also open, already in SPEC_GAP: what "100/day" counts, the weekly approval-time budget value, and exact repeat vs. new revision on 14-day recycling.)

---

## Decisions locked 2026-11-03
Itay's answers, recorded at 16:28 Asia/Jerusalem. They're binding. Schema draft: `migrations/005_critique_alignment.sql`, smoke-tested only in a throwaway in-memory PGlite (`migrations/test_005.sql`). **It hasn't been applied to any live DB.**

| # | Decision (verbatim outcome) | Implication | Where it's applied |
|---|---|---|---|
| **D1** | **YES.** Split BrandGuardian into FactGate + SpecGate (blocking code) and EditorialGuardian (judgment, scores only; it never overrides a block). | `GuardianReport` v2 with `spec` / `fact` / `editorial` sub-reports. Verdict = block if either code gate blocks; otherwise the editorial scores go against the active threshold profile (v0 75/70, unchanged). FactGate reads `usable_facts_v` (approved + public + not expired). The wording "deterministic Guardian gates" becomes "**deterministic Spec+Fact gates + editorial review**". | agents.md (accepted), contracts.md GuardianReport v2, 005 §6, README |
| **D2** | **NO hard freeze.** Edits to approved/scheduled pieces are **audit-only**. No cancelled approval, and no trigger that raises on edit. | **Tradeoff accepted: an approval can survive an edit**, so a published piece may differ from what Itay saw. Mitigation is visibility only: `approved_content_hash` is captured at approval, any later change sets `edited_after_approval` + writes an `audit_log` row, `publish_instances.sent_content_hash` records what was sent, and the mismatch is shown at publish confirmation. Process guidance stays: agents make a **new revision** instead of editing. No `approvals` table, no revoke. | 005 §1, agents.md, contracts.md |
| **D3** | **A.** On an unknown publish outcome, always escalate to Itay. **Never** auto-resend. | `publish_instances` + `publish_attempts` with an `unknown` state. A timeout or lost response → `unknown` + `escalated_at`. The DB refuses a new attempt for an `unknown` instance, and only a human can move it out of `unknown` (confirm live / cancel / fail / explicit re-queue). Auto-retry is only allowed after a **known** transient error (`rate_limit`, `provider_5xx`, `network` returned as an error), up to `max_attempts` (default 2). | 005 §3, agents.md Distributor, contracts.md PublishInstance/PublishAttempt |
| **D4** | **B.** Rules, templates and prompts stay in **Postgres** (`prompt_versions`, `format_specs`, `brand_voice` as today). No migration to Git. | "Memory-as-codebase" = **versioned rows + human approval**, not Git PRs. Additions: fact validity (`last_verified_at`, `valid_until`, `usage_scope`) and ErrorWatcher classification on `correction_log` (`memory_kind`, `rule_reason`, `rule_scope`, `replay_report`). Only `policy_gap` / `fact_change` can be promoted, and only with a replay report. | 005 §6, agents.md ErrorWatcher |
| **D5** | **A.** Add `lead_threads` inside CMK (owner, conversation ref, next_action, proposal, payment status). Content agents don't write or read lead payment details beyond what the handoff fields need. | Agents may only insert `suggested` rows and edit non-gated handoff text. Stage, owner, confirmation, proposal and payment are human-only (trigger). Agents read `lead_handoff_v`, which has no proposal or payment columns. `payment_status` is a coarse flag: **no amounts or prices are stored**. | 005 §5, agents.md Measurement, contracts.md LeadThread |

### Also locked (Itay-default, pending override)
- **The 100/day definition:** four separate counters, (1) new families/cores, (2) new derivatives, (3) repeat publish instances, (4) items awaiting approval. The ~100 goal is mainly **(3) publish instances via reuse + rotation**, not 100 new cores/day. Views: `volume_daily_v`, `approval_queue_v`.
- **Schedule authority:** `rotation_slots` (+ `publish_instances`). Google Calendar is a one-way view, and calendar edits are never read back.
- **14-day recycle:** the current rule stays: recycle = new revision + Guardian + approval, never a verbatim repost. This conflicts with the critique's "exact copy OK", and Itay's existing SPEC wins unless he changes it.
- **Orchestrator:** a `work_items` + `work_transitions` state machine in plain Postgres. Human-only transitions are enforced, attempt_count ≤ max_attempts, and a stop_reason is required on failed/stopped. No Temporal, no workflow engine.

### Superseded proposals
- #2's `approvals` table and freeze trigger → **dropped** (D2).
- #4's Git storage option → **dropped** (D4).
- #3's "auto-resend once after a negative provider lookup" → **dropped** (D3).
