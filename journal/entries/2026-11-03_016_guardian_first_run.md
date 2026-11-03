---
id: J-20261103-016
ts: 2026-11-03T16:55:00+02:00
agent: BrandGuardian
workflow: A
action: spec_fact_editorial_first_run
inputs:
  - runs/001-human-gates/linkedin_text_he.md
  - runs/001-human-gates/linkedin_text_en.md
  - runs/001-human-gates/carousel_he.md
  - runs/001-human-gates/carousel_en.md
  - runs/001-human-gates/core_asset_he.md
  - runs/001-human-gates/core_asset_en.md
  - "guardian/fixtures/approved_facts_db.json (0 approved, 6 draft site facts)"
outputs:
  - guardian/
  - scripts/run_guardian_001.sh
  - runs/001-human-gates/guardian_report_v2/summary.json
  - "runs/001-human-gates/guardian_report_v2/<piece>.{A,B}.json"
status: done
human_gate: pending_itay
notes: "First run of SpecGate + FactGate + EditorialGuardian (heuristic-stub-v0). Variant B (approved): text HE gate=pass verdict=pass brand 88 / ICP 95. Text EN gate=pass verdict=needs_changes (brand 91 / ICP 95): F-T1, the body doesn't open with the approved PR hook; E-DUP, 'same desk' said twice; F-T3 minor, paragraph 381>350. Carousel HE/EN block only on R-01 (not rendered; uncapped 86). Core HE/EN block only on S-02 (⟦ITAY_CONFIRM⟧ anecdote; uncapped 93). Variant A (Stripe paragraph): every piece blocks on B-01, because no approved Stripe/proof fact exists. This is intended. Stub scores are generous and uncalibrated. Gate fix: the checklist v1 B-02 'NIS' regex false-positived on 'finished', so the gate now word-bounds it (checklist v2 proposal). No publishing; nothing was written into content_pieces."
---

First Guardian run on run 001. The HE text is clean. The EN text needs two small fixes before it can be published. Carousels wait on render + RenderQA. Core assets wait on Itay's confirmation of the anecdote. Every Stripe variant is blocked until a proof fact is approved.
