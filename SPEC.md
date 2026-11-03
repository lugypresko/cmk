# SPEC: Content Memory Kitchen (CMK) for The Push

**Version:** 1.0  
**Target Implementers:** Claude / Codex / similar coding agents  
**Goal:** Fully implementable, production-ready agentic content system.

---

## 1. System Overview

**Name:** Content Memory Kitchen (CMK)  
**Purpose:** High-volume, high-trust marketing content system for “The Push”.

**Core Loop:**
1. Human inputs an Idea / Topic / Goal.
2. System produces a research-backed Core Asset + full multi-format Content Package.
3. Human approves (or requests changes).
4. System handles production, scheduling, distribution, and measurement.
5. All learnings and corrections are written back into Business Memory.

**Success Metrics (Primary):**
- Time saved per content cycle (human hours).
- Number of meaningful conversations / engagements generated with ICP.

**Volume Target:**
- ~100 content pieces published per day.
- Achieved via aggressive REUSE + 14-day rolling rotation of a large content library.

---

## 2. Key Domain Concepts

**Product:** The Push – 12-week organizational intervention for growing B2B SaaS companies (typically 50–250 employees). Focus: removing managerial bottlenecks that slow execution.

**ICP:** Technology leaders – Team Leads (ראשי צוות), Group Managers, Directors, CTO, VP R&D.

**Channels:**
- LinkedIn
- Instagram
- Facebook
- X (Twitter)
- itayfoyerstein.com (blog / site)

**Content Formats (must support all):**
1. Carousel (5–10 slides)
2. B-roll / Story (7–15 seconds)
3. Long-form text post
4. X Thread
5. Reels / TikTok (15–30 seconds)
6. YouTube Shorts
7. Infographic / Static image
8. Question / Poll post
9. Interactive Stories
10. Short Email / Newsletter
11. Avatar Video (script + optional generation) – treated as premium add-on

---

## 3. Architecture Principles (Mandatory – from Lauren Tan)

1. **Business Memory = Codebase** — All durable knowledge lives in structured, versioned memory. Agents treat it as source of truth.
2. **Trust First** — Agents only act autonomously after strong verification layers pass.
3. **Make the correct path the easy path** — Constraints, schemas, and rules make bad outputs hard or impossible.
4. **Layered Corrections** (strongest → weakest): Update Business Memory / schemas → Hard validation rules → Skills / prompts → Human review
5. **Feedback Loop** — Every human correction and every performance signal is written back into Memory.

---

## 4. Core Components

### 4.1 Business Memory
Structured, queryable, versioned (Postgres + vector store recommended).

Required: `brand_voice`, `icp_profiles`, `core_insights`, `approved_facts`, `past_content`, `format_specs`, `performance_logs`, `correction_log`, `content_library`.

### 4.2 Agent Roster

| Agent | Responsibility | Autonomy |
|-------|----------------|----------|
| Orchestrator | Full workflow | High |
| ResearchAgent | Research + ICP insights | High |
| CoreCreatorAgent | Core Asset | Medium |
| RepurposerAgent (swarm) | Core → formats | Medium-High |
| BrandGuardianAgent | Brand + ICP + facts | Very High |
| PackageBuilderAgent | Review package | Medium |
| SchedulerAgent | 14-day rotation + daily plan | High |
| DistributorAgent | Publish | High (post-approval) |
| MeasurementAgent | Results → Memory | High |

### 4.3 Workflows
- **A** New Core: Idea → Research → Core → Guardian → Human → Multiply
- **B** Multiply: Core → 11 formats → Guardian → Package → Human (sample at scale) → library
- **C** 14-day rotation: ~100/day, variants/refreshes, Distributor, Measurement

## 5. Data Contracts
See `contracts.md` (CoreAsset, ContentPiece, format payloads).

## 6. Verification Gates
Schema, brand voice, ICP threshold, approved_facts, format rules, Guardian ≥ threshold (SPEC default 0.85).

## 7. Non-Functional
Versioned prompts, audit log, HITL at defined gates, dry-run, extensible, structured JSON.

## 8. Implementation Order
1. Memory schemas + CRUD  
2. BrandGuardian  
3. Core workflow + approval  
4. Repurposer 2–3 formats then expand  
5. Scheduler 14-day  
6. Measurement  
7. Harden verification/autonomy  

Source: pasted by Itay into Grok Bot chat 2026-11-03.
