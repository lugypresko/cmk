# SPEC v1.0 ↔ cmk-memory-v0 gap review (2026-11-03)

**Scope:** SPEC.md is present. CODEX_SPEC_EXECUTION.md limits this implementation to Phase 0–1, LinkedIn text_post/carousel HE/EN and manual distribution at 1/day. D1–D5 remain locked. Historical critique proposals below are superseded by the decision table and execution updates.

Status after this change: ✅ done · 🟡 partial · ❌ missing · **?** unknown (SPEC text needed)

## A. Scope and goals
| SPEC item | Status | Where | v0 choice / note |
|---|---|---|---|
| Idea in → researched multi-format package with approval gates | 🟡 | runtime/orchestrator.mjs | Fixture workflows run to every human gate; optional judgment provider requires approved DB prompt. No production LLM wired. |
| Success = time saved + ICP conversations | 🟡 | performance_logs, measurement_loop.md | Columns and loop are defined. No baseline for time saved yet (Itay sets it). Nothing captured. |
| ~100 pieces/day via 14-day rotation | 🟡 | scheduler_14day.md, migration 002 | Model and algorithm done. **v0 cap is 1 LinkedIn post/day.** The volume is a later ceiling, and it's on purpose. |
| Trust-first: human at start and end | ✅ | CHECKs, triggers, agents.md | It's stricter in v1: format-enabled trigger, stub-inactive CHECK, audit_log. |

## B. Formats (11)
| Format | Enum | format_registry | format_specs | Contract payload | Guardian checks | Enabled | Note |
|---|---|---|---|---|---|---|---|
| text_post | ✅ v0 | ✅ | ✅ active HE/EN | ✅ | ✅ | ✅ | **v0 format #1** |
| carousel | ✅ v0 | ✅ | ✅ active HE/EN | ✅ | ✅ | ✅ | **v0 format #2** |
| x_thread | ✅ 002 | ✅ | 🟡 stub | ✅ | ❌ | no | Replaces v0 `thread`, which stays as legacy |
| broll | ✅ 002 | ✅ | 🟡 stub | ✅ | ❌ | no | Needs MediaProducer + licensing |
| reel | ✅ 002 | ✅ | 🟡 stub | ✅ | ❌ | no | Replaces v0 `short_video_script`, which stays as legacy |
| short | ✅ 002 | ✅ | 🟡 stub | ✅ | ❌ | no | New `youtube` channel |
| infographic | ✅ 002 | ✅ | 🟡 stub | ✅ | ❌ | no | A panel number needs a `fact_id` |
| poll | ✅ 002 | ✅ | 🟡 stub | ✅ | ❌ | no | |
| interactive_story | ✅ 002 | ✅ | 🟡 stub | ✅ | ❌ | no | |
| email | ✅ 002 | ✅ | 🟡 stub | ✅ | ❌ | no | New `email` channel. No list or sending platform |
| avatar | ✅ 002 | ✅ | 🟡 stub | ✅ | ❌ | no | Needs Itay's consent fact + AI disclosure. No provider |
| (v0 `article`) | v0 | legacy | none | none | none | no | Not in the SPEC list as briefed. Kept for the website. **?** |

Stub `format_specs` limits are house defaults or platform limits marked `limits_verified=false`. Each one gets re-checked before its format is enabled. Per-format specs from the SPEC itself: **?**

## C. Guardian
| SPEC item | Status | Where | v0 choice / note |
|---|---|---|---|
| Brand + ICP scoring | 🟡 | guardian/ + runtime/agents.mjs | SpecGate/FactGate built. EditorialGuardian is heuristic-stub-v0; calibration remains open. |
| Threshold 0.85 | 🟡 | guardian_thresholds table + .md | **v0 keeps 75/70 (active).** `spec_v1` 85/85 is seeded inactive. 0–100 is canonical and 0–1 floats are generated. Applying 0.85 to ICP is an assumption. |
| Blockers (facts, pricing, clients, confidentiality, language) | ✅ | guardian_rules §1 | |
| Checks for the 9 new formats | ❌ | guardian_rules §11 | Ids proposed (F-V1, F-P1, F-I1, B-13, B-14). Not written. |

## D. Platform / data
| SPEC item | Status | Where | Note |
|---|---|---|---|
| Business memory (voice, ICP, facts, insights, past content) | ✅ schema / 🟡 data | schema.sql | Facts still `draft`. HE seeds `needs_review`. Past posts not imported (only 2 Stripe Minions seeds as JSON). |
| audit_log | ✅ | 002 §7 | Append-only. Triggers on 9 tables + thresholds. Actor comes from `SET LOCAL cmk.*`. |
| prompt_versions | ✅ schema / 🟡 draft data | 002 + 008 | Three draft/inactive proposals; human approval/activation pending. |
| 14-day rotation columns | ✅ | 002 §5 | `rotation_plans`, `rotation_slots`, content_library `rotation_plan_id/slot_id`, evergreen/recycle. |
| Per-format payload storage | ✅ | content_library.payload + payload_ok() | |
| Media assets (files, licenses) | ✅ v0 PDF QA / 🟡 rendering | 005 media_assets + runtime/files.py | PDF extraction, RTL, fonts, text, count, dimensions, alt and checksum verified. MediaProducer and other extractors deferred. |
| Correction learning loop | 🟡 | correction_log | Schema done. Promotion is manual and unused. |
| Measurement loop | ✅ import / 🟡 data | runtime/production.mjs + 007 | Idempotent xlsx snapshots; unknown human success metrics remain NULL. Baseline pending. |
| Channel integrations (LinkedIn, X, IG/FB, YouTube, email) | ❌ | none | v0 posts manually. Every adapter needs approval. **?** |

## E. Agents
| SPEC item | Status | Note |
|---|---|---|
| Agent roster | 🟡 | 9 agents defined, plus MediaProducer (*proposed, not from the SPEC text*). The SPEC's own roster is **?** |
| Agents as running code | ✅ v0 fixture runtime / 🟡 LLM | Draft wrappers + Orchestrator implemented; no production model provider configured. |
| Orchestration runtime / tech stack | ✅ v0 | Plain PGlite/Postgres state, leases, work_transitions policy and append-only work_events history. |

## F. v0 choices that differ from the SPEC (on purpose)
1. **Thresholds 75/70 instead of 0.85.** One self-estimated calibration run can't justify 85. Under 85/85 the approved run 001 Variant B (est. 81–84 brand) would fail. Revisit after scoring 20+ exemplars.
2. **2 formats first** (LinkedIn text_post and carousel). The other 9 are schema-ready stubs behind `format_registry.v0_enabled` plus a DB trigger.
3. **1 LinkedIn post/day** and per-slot human confirmation. The SPEC's volume comes through ramping `daily_caps`.
4. **Manual distribution** by default.
5. **Recycling = new revision + Guardian + approval.** Never a verbatim repost.

## G. Remaining true gaps (by priority)
1. Human approvals: six draft site facts, HE seeds, real Core and carousel; no agent substitutes.
2. Editorial calibration on 20+ human-labelled exemplars; production LLM provider still optional/unconfigured.
3. Import 20–50 real posts and let Itay mark exemplars; loader exists.
4. Review and activate the draft prompts as a human; Research prompt/provider must be supplied for live generation.
5. Real carousel rendering/visual preview and media storage/licensing policy; v0 PDF RenderQA is built.
6. Time-saved baseline and human-confirmed ICP metrics; xlsx import is built.
7. Hosted DB migrations have not been applied; all validation is local PGlite.
8. Other formats, 85/85 activation, automatic adapters and higher volume are out of this brief.
9. ErrorWatcher candidate-rule replay remains explicitly a stub; promotion remains human-only.

---

## 2026-11-03 GPT architecture critique
Source: a GPT critique Itay pasted on 2026-11-03. Full mapping: `ARCHITECTURE_CRITIQUE_RESPONSE.md`. These are the gaps **not already listed** in sections A–G above. Everything is pending Itay, and nothing has been applied.

| # | Gap | Status | Where today | Proposed fix | Priority |
|---|---|---|---|---|---|
| H-1 | BrandGuardian is called "deterministic", but voice, ICP and source support are semantic | 🟡 | guardian_rules §0/§6, agents.md | Split into FactGate + SpecGate (code, can block) and EditorialGuardian (LLM, scores). `GuardianReport` v2 with 3 sub-reports | P0 |
| H-2 | Approval isn't bound to an exact version: approved rows can be edited (no freeze trigger), and approval doesn't name the assets, account or distribution plan | 🟡 | schema.sql content_library CHECK, 002 audit (logs edits, doesn't block them) | `approvals` table (content_hash, asset_hashes, account_ref, distribution_ref) + freeze trigger | P0 |
| H-3 | No publish attempt log, no `unknown` outcome, no verify-before-retry. The ext-id unique index can't stop a double post after a lost response | ❌ | agents.md Distributor | `publish_instances` + `publish_attempts`, unique attempt ids, provider lookup before any resend | P1 (P0 before any auto-post) |
| H-4 | Memory doesn't separate fact / rule / hypothesis / one-off preference. Facts have no `valid_until`/`last_verified_at`. Rules have no reason or scope | 🟡 | approved_facts (`review_by` only), correction_log | Fact validity columns + `memory_changes` (kind, reason, scope, evidence, test_run_id, approval). `preference_once` is never promotable | P1 |
| H-5 | No automated QA of the rendered file (applies to the v0 carousel PDF too) | 🟡 | agents.md PackageBuilder (Itay preview), MediaProducer proposed | RenderQA step + `media_assets` with sha256 + qa_report. Folds in G.9 | P1 |
| H-6 | Nothing after an ICP conversation: owner, next action, proposal, payment | ❌ | measurement_loop §3 | `lead_threads` handoff (or an external CRM). Content agents never read it | P1 |
| H-7 | "~100/day" doesn't define what gets counted. No approval-capacity model | 🟡 | SPEC §1, scheduler_14day | Count new_families / new_derivatives / repeat_publishes / approval_items separately. Weekly approval budget, value set by Itay | P2 (definition P0) |
| H-8 | Orchestrator state isn't persisted, so there's no per-derivative state, owner, retry limit, stop reason or crash resume | ❌ | agents.md Orchestrator ("not persisted in v0") | `work_items` + `work_transitions` in Postgres (no workflow engine) | P0 |
| H-9 | ErrorWatcher has no classification (content / policy / fact / infra) and no replay test on past examples before approval | 🟡 | agents.md ErrorWatcher | event → classify → propose → replay → approve → new version | P1 |
| H-10 | Two schedule sources: `rotation_slots` and the Google Calendar events from plan 001 | 🟡 | scheduler_14day, rotation_plan_001.md | `rotation_slots`/`publish_instances` are the only authority. Calendar is a one-way view | P1 |
| H-11 | Most of the 9 roles are mechanical but get described as agents | 🟡 | SPEC §4.2, agents.md | Orchestrator, Package, Scheduler, Distributor, Measurement-import, Fact/SpecGate, RenderQA as code. See agents.md "Critique alignment" | P0 (design) |
| H-12 | Exact 14-day repeat vs. the current "always a new revision" rule | **?** | scheduler_14day Recycling | If an exact repeat is allowed: a repeat count or end date, a fact-validity check, and a stop when a fact changes. **Conflicts with F.5, so Itay decides** | P2 |
| H-13 | Rules, templates and prompts in Git vs. Postgres (what "memory-as-codebase" means) | **?** | SPEC §3.1, 002 prompt_versions | Git for rules/prompts/templates, Postgres for facts/approvals/artifacts/state, object storage for media. Or keep it as is | P1 |
| H-14 | Journal status vocabulary drift: entry 012 uses `proposed`, which `cmk.agent_journal.status` CHECK doesn't allow | 🟡 | migrations/004, journal 012 | Add `proposed` to the CHECK in the next migration, or use `done` + `human_gate` | P2 |

**Already covered (no change):** version-gated prompts, the human-only `approved_by` CHECK, format-enabled gates, ErrorWatcher propose-only, 2 formats first, volume as a cap, recycle = new revision + re-approval, avatar consent + disclosure (B-13), Measurement never feeds Guardian, small n treated as a hypothesis.

### Decision status (locked 2026-11-03, 16:28 Asia/Jerusalem)
Itay decided D1–D5 (`ARCHITECTURE_CRITIQUE_RESPONSE.md` → *Decisions locked*). Schema draft: `migrations/005_critique_alignment.sql` + `test_005.sql`. It's smoke-tested in a throwaway in-memory DB only and **not applied to a live DB**. "In progress" = designed and drafted in docs/SQL, not yet applied or running as code.

| # | Decision | New status | Note |
|---|---|---|---|
| H-1 | D1 yes | ✅ code / 🟡 calibration | Code gates block, editorial stub scores; block cap remains 74. |
| H-2 | D2 no freeze | ✅ decided · 🟡 in progress | **Audit-only** (005 §1: hash at approval, `edited_after_approval`, audit row). No approvals table, no revoke. Accepted risk: approval can survive an edit |
| H-3 | D3 = A | ✅ v0 manual | Manual instance/attempt path; unknown refuses retries, human resolves. No publishing adapter. |
| H-4 | D4 = B | ✅ decided · 🟡 in progress | Stays in Postgres. 005 §6 adds fact validity + `memory_kind`/replay columns |
| H-5 | (follows D1) | ✅ PDF QA / 🟡 media production | RenderQA built; run001 placeholder tested; real human carousel approval open. |
| H-6 | D5 = A | ✅ decided · 🟡 in progress | 005 §5 `lead_threads` + `lead_handoff_v`. Proposal/payment are human-only |
| H-7 | Itay-default | ✅ decided (default, pending override) · 🟡 in progress | 4 counters. ~100/day = mainly publish instances. `volume_daily_v`, `approval_queue_v` |
| H-8 | Itay-default | ✅ v0 runtime | Durable steps, leases, attempts, stop reasons and per-derivative waits tested. |
| H-9 | (follows D4) | 🟡 explicit stub | Classification/proposal and baseline fixture replay implemented; no auto-promotion. |
| H-10 | Itay-default | ✅ decided | `rotation_slots` is the authority. Calendar is a one-way view |
| H-11 | (follows D1) | ✅ decided | Code vs. agents table in agents.md |
| H-12 | Itay-default | ✅ decided: **keep** new revision + gates + approval | The critique's exact-copy option is rejected unless Itay changes the SPEC |
| H-13 | D4 = B | ✅ decided: **Postgres**, no Git | Closed |
| H-14 | n/a | ✅ | 005 journal vocabulary includes proposed; new entries mirrored into DB. |

**Hosted deployment pending:** no hosted DB was touched. Local code status is recorded above; human content gates stay open.

## Phase A execution (2026-11-03)
Memory applies locally with SQL smoke tests; checklist v2 B-02 is seeded in Postgres (006) and exported to fixtures. Human approvals remain open. See docs/OPERATIONS.md. Hosted DB untouched.

## Phase B execution (2026-11-03)
RenderQA + package + measurement/past-content import code and tests exist in runtime/.
PDF-only RenderQA fails closed on missing extraction/RTL/font evidence. Full MediaProducer rendering
and human visual approval remain open. 20–50 real posts and success baselines still require Itay.
Measurement identity is enforced by migration 007; missing ICP conversations remain NULL.

## Phase C execution (2026-11-03)
Work-item runtime, leases, atomic draft creation and append-only work_events now exist. Research/Core/
Repurposer wrappers validate draft output; Guardian reads live DB context; editorial is explicitly
heuristic-stub-v0. Prompt proposals are draft/inactive in Postgres (008). ErrorWatcher proposes and writes
a clearly labelled baseline replay stub. Human approval and prompt activation remain open.

## Phase D execution (2026-11-03)
Scheduler proposes draft plans with unconfirmed filled/open slots; confirms only with explicit human ID,
current approved package and cross-plan 1/day cap. Distributor records manual attempts and explicit URLs.
Unknown outcomes refuse resend; no network publishing adapter exists. 009–010 strengthen human approval,
lead owner, exemplar and memory promotion boundaries while preserving D2 audit-only edits.
