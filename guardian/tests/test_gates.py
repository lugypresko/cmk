"""Unit tests: python3 -m unittest discover -s guardian/tests -t ."""
import unittest

from guardian import editorial_guardian, fact_gate, spec_gate
from guardian.common import FIXTURES, load_context, load_facts
from guardian.report import assemble

CTX = load_context()
FACTS = load_facts(FIXTURES / "facts_TEST_ONLY.json")
F1 = "00000000-0000-4000-8000-000000000001"

BASE = ("Your team brought in agents. The decisions still come back to you.\n\n"
        "I keep hearing this from dev managers. The PR waits for one last look.\n\n" + ("Gate the rules. Keep the judgment at the end. " * 12) +
        "\n\nIn your team's flow, where does the human sit: at the start and the end, or in the middle?")


def piece(body=BASE, **kw):
    p = {"contract": "cmk/ContentPiece", "format": "text_post", "channel": "linkedin", "language": "en",
         "status": "draft", "body": body, "hashtags": [], "fact_ids": [], "revision": 1}
    p.update(kw)
    return p


def ids(rep):
    return {f["check_id"] for f in rep["findings"] if f["severity"] == "blocker"}


class SpecGateTests(unittest.TestCase):
    def test_clean_passes(self):
        self.assertTrue(spec_gate.check(piece(), CTX)["pass"])

    def test_pricing_blocks(self):
        self.assertIn("B-02", ids(spec_gate.check(piece(BASE + "\nFirst session is 20% off: ₪500."), CTX)))

    def test_finished_is_not_nis(self):
        self.assertNotIn("B-02", ids(spec_gate.check(piece("The agent finished the PR. " + BASE), CTX)))

    def test_hebrew_in_en_blocks(self):
        self.assertIn("B-06", ids(spec_gate.check(piece(BASE + " שלום"), CTX)))

    def test_mostly_english_he_blocks(self):
        self.assertIn("B-06", ids(spec_gate.check(piece(BASE, language="he"), CTX)))

    def test_guarantee_blocks(self):
        self.assertIn("B-07", ids(spec_gate.check(piece(BASE + " Guaranteed results."), CTX)))

    def test_carousel_limits(self):
        sl = [{"n": i, "headline": f"h{i}", "text": "t"} for i in range(1, 12)]
        r = spec_gate.check(piece("caption " * 30, format="carousel", slides=sl), CTX, media_qa="pass")
        self.assertIn("B-11", ids(r))
        sl2 = [{"n": i, "headline": f"h{i}", "text": "t"} for i in (1, 2, 4, 5, 6)]
        self.assertIn("F-C1", ids(spec_gate.check(piece("caption " * 30, format="carousel", slides=sl2), CTX, media_qa="pass")))

    def test_placeholder_blocks(self):
        self.assertIn("S-02", ids(spec_gate.check(piece(BASE + " ⟦ITAY_CONFIRM⟧"), CTX)))

    def test_agent_approver_blocks(self):
        r = spec_gate.check(piece(status="approved", approved_by="agent", approved_at="x", brand_score=80, icp_relevance_score=80), CTX)
        self.assertIn("B-09", ids(r))


class FactGateTests(unittest.TestCase):
    def test_unsourced_third_party_number_blocks(self):
        r = fact_gate.check(piece(BASE + "\n\nStripe merges 1,000 PRs a week with Minions."), FACTS)
        self.assertFalse(r["pass"]); self.assertTrue(r["unsupported_claims"])

    def test_approved_fact_listed_passes(self):
        r = fact_gate.check(piece(BASE + "\n\nI've spent 25+ years in technology and delivery.", fact_ids=[F1]), FACTS)
        self.assertTrue(r["pass"], r["findings"])

    def test_approved_fact_not_listed_blocks(self):
        self.assertFalse(fact_gate.check(piece(BASE + "\n\n25+ years in technology and delivery."), FACTS)["pass"])

    def test_stronger_number_blocks(self):
        r = fact_gate.check(piece(BASE + "\n\n30 years in technology and delivery.", fact_ids=[F1]), FACTS)
        self.assertFalse(r["pass"])
        self.assertEqual([c["status"] for c in r["claims"] if c["kind"] == "fact"], ["stronger_fail"])

    def test_expired_fact_blocks(self):
        r = fact_gate.check(piece(BASE + "\n\nOver 1000+ coaching hours."), FACTS)
        self.assertFalse(r["pass"])

    def test_draft_fact_id_blocks_b08(self):
        r = fact_gate.check(piece(fact_ids=["00000000-0000-4000-8000-000000000003"]), FACTS)
        self.assertIn("B-08", ids(r))

    def test_quantified_experience_is_fact(self):
        r = fact_gate.check(piece(BASE + "\n\n80% of the managers I coach say this."), FACTS)
        self.assertFalse(r["pass"])

    def test_pre_extracted_claims(self):
        r = fact_gate.check(piece(), FACTS, claims=[{"text": "25+ years", "kind": "fact", "fact_id": F1}])
        self.assertFalse(r["pass"])  # F1 usable but not listed in fact_ids
        r = fact_gate.check(piece(fact_ids=[F1]), FACTS, claims=[{"text": "25+ years", "kind": "fact", "fact_id": F1},
                                                                 {"text": "I keep seeing this", "kind": "experience"}])
        self.assertTrue(r["pass"])


class ReportTests(unittest.TestCase):
    def test_editorial_cannot_unblock(self):
        p = piece(BASE + " 20% off.")
        s, f = spec_gate.check(p, CTX), fact_gate.check(p, FACTS)
        e = editorial_guardian.score(p, CTX, s, f)
        e["brand_score"] = e["icp_relevance_score"] = 100
        rep = assemble(p, s, f, e, CTX)
        self.assertEqual(rep["gate_verdict"], "block")
        self.assertEqual(rep["verdict"], "needs_changes")
        self.assertLessEqual(rep["brand_score"], CTX["thresholds"]["brand_cap_when_blocked"])

    def test_hype_penalised(self):
        p = piece("Devs: 10x your output with Claude agents! Crush it! Let agents ship straight to prod.")
        e = editorial_guardian.score(p, CTX, spec_gate.check(p, CTX), fact_gate.check(p, FACTS))
        self.assertLess(e["brand_score"], 50)


if __name__ == "__main__":
    unittest.main()
