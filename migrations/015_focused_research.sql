-- 015: The Push focused social-research profile and research.v0 draft version 2.
-- Postgres remains the source of truth (D4). Existing prompt versions are untouched.
-- No profile/prompt is activated or approved by this migration.
BEGIN;
SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='Codex'; SET LOCAL cmk.run_id='phase-0-4-research';
SET LOCAL search_path=cmk,public;
CREATE TABLE IF NOT EXISTS research_profiles (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 profile_key text NOT NULL CHECK(profile_key ~ '^[a-z0-9_.]+$'),
 version integer NOT NULL CHECK(version>0),
 body jsonb NOT NULL CHECK(jsonb_typeof(body)='object'),
 status memory_status NOT NULL DEFAULT 'draft',
 is_active boolean NOT NULL DEFAULT false,
 approved_by text,
 approved_at timestamptz,
 created_by actor_type NOT NULL DEFAULT 'agent',
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(profile_key,version),
 CHECK(status<>'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
 CHECK(NOT is_active OR status='approved')
);
CREATE UNIQUE INDEX IF NOT EXISTS research_profiles_one_active ON research_profiles(profile_key) WHERE is_active;
CREATE OR REPLACE FUNCTION research_profile_boundary() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_actor text:=coalesce(nullif(current_setting('cmk.actor_type',true),''),'agent');
BEGIN
 IF TG_OP='UPDATE' AND (NEW.body IS DISTINCT FROM OLD.body OR NEW.profile_key IS DISTINCT FROM OLD.profile_key OR NEW.version IS DISTINCT FROM OLD.version) THEN
  RAISE EXCEPTION 'research profile body/key/version are immutable; insert a new version';
 END IF;
 IF v_actor<>'human' THEN
  IF TG_OP='INSERT' THEN
   IF NEW.status<>'draft' OR NEW.is_active OR NEW.approved_by IS NOT NULL OR NEW.approved_at IS NOT NULL THEN
    RAISE EXCEPTION 'research profile approval and activation are human-only'; END IF;
  ELSIF NEW.status IS DISTINCT FROM OLD.status OR NEW.is_active IS DISTINCT FROM OLD.is_active
     OR NEW.approved_by IS DISTINCT FROM OLD.approved_by OR NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN
   RAISE EXCEPTION 'research profile approval and activation are human-only';
  END IF;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS research_profile_boundary ON research_profiles;
CREATE TRIGGER research_profile_boundary BEFORE INSERT OR UPDATE ON research_profiles FOR EACH ROW EXECUTE FUNCTION research_profile_boundary();
DROP TRIGGER IF EXISTS research_profiles_audit ON research_profiles;
CREATE TRIGGER research_profiles_audit AFTER INSERT OR UPDATE OR DELETE ON research_profiles FOR EACH ROW EXECUTE FUNCTION audit_status_change();
INSERT INTO research_profiles(profile_key,version,body,status,is_active,created_by)
VALUES('the_push.social_research',1,$profile${
  "name": "The Push focused social research",
  "brand_key": "the_push",
  "languages": [
    "he",
    "en"
  ],
  "recency_days": 30,
  "max_queries": 12,
  "max_results_per_query": 10,
  "max_sources": 30,
  "primary_platform": "linkedin",
  "platforms": [
    "linkedin",
    "reddit",
    "x"
  ],
  "managerial_terms_he": [
    "מנהל",
    "ניהול",
    "מנהיגות",
    "צוואר בקבוק",
    "החלטה",
    "בעלות",
    "אחריות",
    "האצלה",
    "סמכות",
    "ביצוע"
  ],
  "managerial_terms_en": [
    "manager",
    "management",
    "leadership",
    "engineering leadership",
    "decision",
    "ownership",
    "accountability",
    "delegation",
    "authority",
    "execution",
    "review bottleneck"
  ],
  "clusters": [
    {
      "id": "manager_bottleneck",
      "label": "Manager as a bottleneck",
      "keywords_he": [
        "צוואר בקבוק ניהולי",
        "תלות במנהל",
        "החלטות שחוזרות למנהל",
        "אישורים",
        "הסלמות"
      ],
      "keywords_en": [
        "manager bottleneck",
        "decision latency",
        "approval bottleneck",
        "manager dependency",
        "review bottleneck"
      ],
      "managerial_question": "Where does work or decision-making wait for the manager, and what could change that?"
    },
    {
      "id": "leadership_delegation",
      "label": "Leadership and delegation",
      "keywords_he": [
        "מנהלי פיתוח",
        "ראשי צוותים",
        "פיתוח מנהלים",
        "האצלת סמכויות",
        "עצמאות צוות"
      ],
      "keywords_en": [
        "engineering leadership",
        "delegation",
        "manager development",
        "team autonomy",
        "decision ownership"
      ],
      "managerial_question": "How can managers develop people and distribute decision authority without losing accountability?"
    },
    {
      "id": "ownership_execution",
      "label": "Ownership and execution",
      "keywords_he": [
        "בעלות על תוצאה",
        "אחריות",
        "כיבוי שריפות",
        "אסטרטגיה לביצוע",
        "יכולת ביצוע"
      ],
      "keywords_en": [
        "ownership",
        "accountability",
        "execution",
        "delivery predictability",
        "strategy to execution"
      ],
      "managerial_question": "How does the team turn activity into owned, predictable business outcomes?"
    },
    {
      "id": "ai_management",
      "label": "Management in the AI era",
      "keywords_he": [
        "סוכני AI בצוותי פיתוח",
        "ניהול בעידן AI",
        "תפקיד מנהל הפיתוח",
        "עומס סקירות",
        "שיקול דעת אנושי"
      ],
      "keywords_en": [
        "AI engineering management",
        "agentic development",
        "human oversight",
        "engineering manager AI",
        "agent review workload"
      ],
      "managerial_question": "What changes in management work when agents increase output and review or approval pressure?"
    },
    {
      "id": "ai_code_factory",
      "label": "AI Code Factory",
      "keywords_he": [
        "מפעל קוד",
        "מערכות שיוצרות מערכות",
        "שערי אימות",
        "תזמור סוכנים",
        "סוכני קוד"
      ],
      "keywords_en": [
        "AI code factory",
        "software factory",
        "coding agents",
        "verification gates",
        "agent orchestration",
        "systems that create systems"
      ],
      "managerial_question": "How should leaders design requirements, verification and human judgment in an agent-powered software factory?"
    }
  ],
  "query_pairs": [
    {
      "id": "agent_review_bottleneck",
      "terms_he": [
        "סוכני AI",
        "צוואר בקבוק",
        "סקירות"
      ],
      "terms_en": [
        "coding agents",
        "review bottleneck"
      ]
    },
    {
      "id": "factory_leadership",
      "terms_he": [
        "מפעל קוד",
        "ניהול פיתוח"
      ],
      "terms_en": [
        "AI code factory",
        "engineering leadership"
      ]
    },
    {
      "id": "delegation_decisions",
      "terms_he": [
        "האצלת סמכויות",
        "בעלות על החלטות"
      ],
      "terms_en": [
        "delegation",
        "decision ownership"
      ]
    },
    {
      "id": "agents_managers",
      "terms_he": [
        "סוכני AI",
        "מנהל פיתוח"
      ],
      "terms_en": [
        "coding agents",
        "engineering manager"
      ]
    },
    {
      "id": "delegation_bottleneck",
      "terms_he": [
        "האצלת סמכויות",
        "צוואר בקבוק"
      ],
      "terms_en": [
        "delegation",
        "manager bottleneck"
      ]
    },
    {
      "id": "verification_oversight",
      "terms_he": [
        "שערי אימות",
        "שיקול דעת אנושי"
      ],
      "terms_en": [
        "verification gates",
        "human oversight"
      ]
    }
  ],
  "exclusion_terms": [
    "generic AI news without a management implication",
    "tool lists without a management implication",
    "coding tutorials without a management implication",
    "unrelated uses of The Push brand words"
  ],
  "relevance_rules": [
    "A finding must match at least one focus cluster and explain an implication for managers developing people, distributing authority, making decisions, or turning output into outcomes.",
    "Treat The Push as a positioning and supplementary brand-search anchor; discover the language of the audience problems even when the brand is not mentioned.",
    "Keep the active Business Memory ICP and positioning authoritative; public popularity alone never makes a topic relevant."
  ],
  "report_targets": {
    "topics": 5,
    "hook_examples": 5,
    "recommended_angles": 3,
    "original_hooks_per_angle": 3,
    "selected_insights": 1
  },
  "evidence_rules": [
    "Use actual accessible public posts/discussions and comments when available. Preserve source IDs, URLs, platform, source publication date when known and capture time; unknown dates remain null with a coverage note.",
    "Engagement observations must come from captured evidence with an observation timestamp; unavailable values stay null, never inferred.",
    "Observed engagement is not business effectiveness. Use business_effectiveness_unknown unless directly measured outcome evidence exists.",
    "Compare relative performance only when comparable baseline evidence was captured. Do not infer reach, conversion, ICP fit or sales from likes alone.",
    "Do not label a small or incomplete sample as a platform-wide trend. State search/access/recency/metric coverage limits and insufficient evidence explicitly.",
    "Collected source observations are candidate evidence, not approved_facts. Factual claims intended for publication still require usable approved facts and human review.",
    "Verify original hook examples only from full captured post text with source kind full_post. Search snippets are candidate discovery text, not proof of the original opening or performance. imported_excerpt evidence also cannot prove the opening. Do not copy posts or hooks as new content; keep source excerpts short and attributed and generate original hook candidates from observed mechanisms.",
    "No access to private groups, private conversations or viewer identity analytics. No invented clients, quotes, testimonials, numbers or consent."
  ]
}$profile$,'draft',false,'agent')
ON CONFLICT(profile_key,version) DO NOTHING;
INSERT INTO prompt_versions(agent,prompt_key,version,body,params,parent_id,created_by,change_note)
SELECT 'research','research.v0',2,$research$Perform focused social research for The Push before choosing a content topic. Read the supplied research_profile, active Business Memory positioning and ICP, idea/source notes, and the collected documented evidence. The Push is the positioning anchor, not the only search keyword. Focus on manager bottlenecks, leadership/delegation, ownership/execution, AI engineering management, and AI Code Factory/verification/agent orchestration. Exclude generic AI news, tool lists and coding tutorials unless their implication for leadership, decision authority, review bottlenecks or business execution is explicit.

Use the real evidence supplied by the source collector, not model recollection or invented searches. Identify current recurring questions, frustrations, disagreements and changes in audience discussions, including comments when captured. Analyze relevant topic/hook examples from Itay and other creators when available: opening, angle, structure and the discussion observed. Refer to captured source_ids and explain why each finding fits The Push and the active ICP. Source IDs must exist in the supplied evidence. A topic, hook example or angle may not claim evidence that was not collected.

Keep actual metrics only in the evidence records, never generate or repeat metric values in research_report. Distinguish observed_engagement from business_effectiveness_unknown. Likes alone are not proof of effectiveness; relative-performance or outcome claims require actual comparable evidence. If metrics, comments, publication dates, access or coverage are missing, state the limitation. A small sample is a hypothesis, not a platform-wide trend. Do not claim to have read a source beyond its captured text. A verified hook example requires full captured post text with source kind full_post. Search snippets and imported_excerpt records may suggest candidate hooks but cannot establish the original post opening, discussion quality or performance. When verified opening evidence is unavailable, leave hook_examples empty and record that gap rather than promote a snippet. Do not copy a source hook as an original hook; keep quoted excerpts short and attributed, and propose original wording based on the mechanism observed.

Return one draft JSON object with title, insight_he and/or insight_en, confidentiality ('public' or 'anonymized'), status:'draft', and research_report containing topics[], hook_examples[], recommended_angles[], recommended_topic and coverage_notes[]. Aim for the report_targets in research_profile only when evidence supports them; never pad an incomplete sample to meet a count. Topic entries explain the managerial pain and relevance and reference source_ids. Hook examples reference source_ids and separate the observed mechanism from hypotheses about why it attracted discussion. Recommended angles reference source_ids, explain the original The Push contribution and may propose original hooks. recommended_topic is an object {title,source_ids,uncertainty}, selecting one evidenced direction for the Core and explaining uncertainty. TopicResearchAgent and HookResearchAgent outputs supplied to you are draft analyses, not new evidence; verify their source_ids and claims against the original collected evidence before synthesis. If evidence is insufficient, say so and do not present invented examples or success claims. Proposed originality is not observed performance.

After research, derive one insight from the supplied idea or source materials: a title and content in Hebrew and/or English. Supplied source materials include the collected documented findings with URLs/dates; collecting a source does not approve its factual assertions. Use only supplied material, usable approved public facts and active Business Memory. Never invent facts, numbers, sources, client names or quotations. External factual assertions intended for publication remain candidates needing verification/approval; do not silently promote them to approved facts. Set confidentiality to public or anonymized, remove identifying details of private clients/people, and state missing evidence rather than filling gaps. Output draft only for human review and approval. Never approve a prompt, fact, insight, content piece, publication or paid request.$research$,
 '{"research_profile_key":"the_push.social_research","research_profile_version":1,"requires_collected_evidence":true,"topic_prompt_key":"research.topics.v0","hook_prompt_key":"research.hooks.v0"}'::jsonb,
 (SELECT id FROM prompt_versions WHERE prompt_key='research.v0' AND version=1),
 'agent','Focused The Push social listening + topic/hook research + one source-grounded draft insight; human review pending'
WHERE NOT EXISTS(SELECT 1 FROM prompt_versions WHERE prompt_key='research.v0' AND version=2);
INSERT INTO prompt_versions(agent,prompt_key,version,body,params,created_by,change_note)
SELECT 'research','research.topics.v0',1,$topics$Act as TopicResearchAgent for The Push, one bounded research role in CMK. Use only the supplied focused research_profile, active Business Memory/ICP, idea/source notes and actual collected evidence. Focus on manager bottlenecks, leadership/delegation, ownership/execution, AI engineering management and AI Code Factory with a clear managerial implication. Exclude generic AI news, unrelated tools or tutorials. Identify audience questions, pains, disagreements and relevant changes visible in the captured text; read comments only if the collector actually supplied them. Never claim a search snippet or imported_excerpt is a complete post or a platform-wide trend. Return one JSON object {topics:[],coverage_notes:[],status:"draft"}. Each topic entry contains a topic/title, the managerial pain, why it fits The Push and source_ids drawn only from the supplied evidence. Up to five topics is a target, not a quota: fewer or none is correct when coverage is insufficient. Do not emit metric values, fabricated counts, success claims, client names or invented quotations. Coverage notes must state missing access, dates, comments, baseline/metrics or sample limitations; observed discussion is not proven business effectiveness. Treat external assertions as candidate evidence, never approved facts. Output draft only; no fact, content, prompt, payment or publishing approval.$topics$,
 '{"research_profile_key":"the_push.social_research","research_profile_version":1,"requires_collected_evidence":true,"runtime_role":"topics"}'::jsonb,
 'agent','TopicResearchAgent: source-grounded The Push pains/topics; human review pending'
WHERE NOT EXISTS(SELECT 1 FROM prompt_versions WHERE prompt_key='research.topics.v0' AND version=1);
INSERT INTO prompt_versions(agent,prompt_key,version,body,params,created_by,change_note)
SELECT 'research','research.hooks.v0',1,$hooks$Act as HookResearchAgent for The Push, a bounded role distinct from topic discovery and final insight synthesis. Use only the supplied research_profile, active Business Memory/ICP and actual collected evidence about management bottlenecks, leadership/delegation, ownership/execution, AI management and AI Code Factory. Return one JSON object {hook_examples:[],recommended_angles:[],coverage_notes:[],status:"draft"}. Each verified hook example has source_ids, observed_opening and mechanism. observed_opening must be an exact leading opening excerpt of captured source text whose source kind is full_post; do not rewrite, paraphrase or take a later sentence as the observed opening. search_snippet and imported_excerpt records cannot prove an original post opening: they may inform source-referenced candidate angles/original hooks, but leave verified hook_examples empty and state the gap when no full_post evidence exists. Do not add performance_claim or metric values. Actual observed metrics remain in evidence records. Distinguish observed_engagement from business_effectiveness_unknown; likes alone or a search ranking never prove successful content or conversion. Explain opening mechanisms as hypotheses, not causal facts; relative performance requires captured comparable baseline evidence. recommended_angles may contain {angle,original_hooks:[],source_ids}; generate original candidate wording relevant to The Push rather than copying a source hook, and never present these candidates as already successful. Aim for up to five verified examples, three angles and three original hooks per angle only when source coverage supports them. Keep attributed source excerpts short. State missing comments, dates, metrics, access and coverage in nonempty coverage_notes. No invented clients, testimonials, numbers, sources or quotes. Output draft only, with no authority to approve or publish.$hooks$,
 '{"research_profile_key":"the_push.social_research","research_profile_version":1,"requires_collected_evidence":true,"runtime_role":"hooks"}'::jsonb,
 'agent','HookResearchAgent: verified full-post openings and original candidate angles; human review pending'
WHERE NOT EXISTS(SELECT 1 FROM prompt_versions WHERE prompt_key='research.hooks.v0' AND version=1);
COMMIT;
