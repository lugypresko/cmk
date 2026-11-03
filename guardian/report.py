"""Assemble GuardianReport v2 (contracts.md §v2): {spec, fact, editorial, verdict} +
derived v0 top-level fields. Code gates decide first; editorial can't unblock."""
from __future__ import annotations

from .common import now_iso


def assemble(piece: dict, spec: dict, fact: dict, editorial: dict, ctx: dict) -> dict:
    th = ctx["thresholds"]
    gate_block = (not spec["pass"]) or (not fact["pass"])
    brand_raw, icp = editorial["brand_score"], editorial["icp_relevance_score"]
    brand = min(brand_raw, th["brand_cap_when_blocked"]) if gate_block else brand_raw
    rev = piece.get("revision") or 1
    # S-01 "approved without scores" is resolved by attaching this report's scores at insert time,
    # so it doesn't hold the verdict back; every other major does.
    majors = sorted({f["check_id"] for f in spec["findings"] + fact["findings"] + editorial["findings"]
                     if f["severity"] == "major" and not (f["check_id"] == "S-01" and "requires brand_score" in f["message"])})
    if gate_block:
        verdict = "reject" if rev >= ctx["checklist"]["thresholds"]["reject_if_blocked_at_revision_gte"] else "needs_changes"
        reason = "code gate blocked (" + ", ".join(n for n, r in (("SpecGate", spec), ("FactGate", fact)) if not r["pass"]) + ")"
    elif brand < th["reject_brand_below"] or icp < th["reject_icp_below"]:
        verdict, reason = "reject", "off-strategy scores (recommend_reject; only a human sets rejected)"
    elif majors:
        verdict, reason = "needs_changes", "no blockers, but major findings need a fix or explicit human waiver: " + ", ".join(majors)
    elif brand >= th["brand_min"] and icp >= th["icp_min"]:
        verdict, reason = "pass", f"gates pass; brand {brand}>={th['brand_min']} and ICP {icp}>={th['icp_min']}"
    else:
        verdict, reason = "needs_changes", f"below threshold (brand {brand}/{th['brand_min']}, ICP {icp}/{th['icp_min']})"
    findings = spec["findings"] + fact["findings"] + editorial["findings"]
    meta = piece.get("_meta", {})
    return {
        "$schema": "cmk/GuardianReport.v2",
        "piece": {"source_path": meta.get("source_path"), "source_sha256": meta.get("source_sha256"),
                  "variant": meta.get("variant"), "loader_notes": meta.get("loader_notes"),
                  "contract": piece.get("contract"), "format": piece.get("format"), "channel": piece.get("channel"),
                  "language": piece.get("language"), "revision": rev, "status_in_file": piece.get("status"),
                  "approved_by_in_file": piece.get("approved_by")},
        "gate_verdict": "block" if gate_block else "pass",
        "verdict": verdict,
        "verdict_reason": reason,
        "spec": {k: spec[k] for k in ("pass", "verdict", "checklist_version", "format_spec_id", "findings")},
        "fact": {k: fact[k] for k in ("pass", "verdict", "claims", "unsupported_claims", "findings", "facts_considered")},
        "editorial": editorial,
        # derived v0/v1 fields
        "brand_score": brand,
        "brand_score_uncapped": brand_raw,
        "icp_relevance_score": icp,
        "findings": findings,
        "unsupported_claims": fact["unsupported_claims"],
        "threshold_profile": th["profile"],
        "brand_voice_version": ctx["brand_voice"].get("version"),
        "counts": {s: sum(1 for f in findings if f["severity"] == s) for s in ("blocker", "major", "minor", "info")},
        "checked_at": now_iso(),
        "checked_by": "guardian v0 (SpecGate+FactGate code; EditorialGuardian heuristic stub)",
    }
