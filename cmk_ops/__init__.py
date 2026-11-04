"""cmk_ops — CMK role modules for the v0 E2E slice (grill decisions G1–G14, 2026-11-04).

Code, not chat teammates. This drop ships:
  canon.py            package hash (copy + assets + account + language + repeat windows; no first_comment)
  carousel_render.py  HE Run001 Variant B carousel. `python -m cmk_ops` and the demo `build` command use this.
  carousel.py         alternate layout/RenderQA helper. Not the demo entrypoint.
  common.py           local out dir, clock, append-only events.jsonl

Brief, Ingest, Research, and LeadOps stay stubs. See runs/001-human-gates/out/stubs_journal.md.
Postgres gates: migrations/012_e2e_chain_slice.sql (renumbered from the local 006; 006–011 on this branch are unchanged).
Demo state: runs/001-human-gates/out/. No auto-publish.
"""
