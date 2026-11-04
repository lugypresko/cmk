# The Push research prompt and focus profile

Migration 015 proposes `research.v0` version 2, two bounded runtime-role prompts and
`the_push.social_research` profile version 1. All are **draft and inactive**. It does not alter or activate version 1, approve facts, grant paid
access or authorize publication. Postgres is authoritative for the prompt and focus policy (D4).
This document explains the seeded proposal; it is not a second executable prompt store.

## Focus

| Profile cluster | Hebrew examples | English examples | Leadership question |
|---|---|---|---|
| `manager_bottleneck` | צוואר בקבוק ניהולי, תלות במנהל, אישורים | manager bottleneck, decision latency, approval bottleneck | Where does work wait for the manager? |
| `leadership_delegation` | מנהלי פיתוח, האצלת סמכויות, עצמאות צוות | engineering leadership, delegation, team autonomy | How can authority and judgment move closer to the team? |
| `ownership_execution` | בעלות על תוצאה, כיבוי שריפות, אסטרטגיה לביצוע | ownership, accountability, delivery predictability | How does activity become owned, predictable outcomes? |
| `ai_management` | ניהול בעידן AI, סוכני AI בצוותי פיתוח, עומס סקירות | AI engineering management, agentic development, human oversight | What managerial work changes when agents increase output? |
| `ai_code_factory` | מפעל קוד, מערכות שיוצרות מערכות, שערי אימות | AI code factory, coding agents, verification gates | How should leaders place requirements, verification and human judgment? |

The active Business Memory ICP and positioning remain authoritative. The Push is a positioning and
supplementary brand-search anchor, not a requirement that the brand name appear in every finding.
The query plan combines cluster terms, for example coding agents + review bottleneck, AI code factory
+ engineering leadership, delegation + decision ownership, and סוכני AI + מנהל פיתוח.
Generic AI news, unrelated tools and coding tutorials are excluded unless their management implication
is explicit: developing people, distributing authority, making decisions or turning output into outcomes.

The draft house defaults are HE+EN, LinkedIn as primary with public Reddit/X context, a 30-day recency
window, at most 12 queries / 10 results per query / 30 source records. These are bounded collection
settings rather than claims about the market. Missing source access, dates, comments or metrics must
remain visible in coverage notes. Changing approved policy/body requires a new profile version.

## Source-grounded output

The collector, not model recollection, supplies actual evidence with source IDs, URLs, capture dates,
known publication dates, excerpts and any observed metrics. Unknown publication dates/metrics stay null.
A search snippet is discovery evidence, not proof that it is the source post's opening. A verified hook
example needs full captured post text with source kind `full_post`; `search_snippet` and `imported_excerpt` cannot prove an original opening. With only snippets,
return no verified hook examples and explain the gap; never relabel snippets as successful openings.

The v2 research output extends the existing draft insight shape:

```text
{
  title,
  insight_he and/or insight_en,
  confidentiality: public | anonymized,
  status: draft,
  research_report: {
    topics[],
    hook_examples[],
    recommended_angles[],
    recommended_topic: {title, source_ids, uncertainty},
    coverage_notes[]
  }
}
```

Topics, sourced hook examples and recommended angles reference only source IDs from the collected
bundle. Up to five topics, five verified hook examples and three angles are targets, not quotas to pad.
Angles may propose up to three original hooks; such hooks are proposals without observed performance.
`recommended_topic` chooses one evidenced direction and explains uncertainty and The Push relevance.
Metric values reside only in captured evidence records, never in model-generated report fields.

Use `observed_engagement` only for actual engagement observations and keep `business_effectiveness_unknown`
unless real outcome evidence exists. Likes alone do not prove business effectiveness. Relative-performance
claims require captured comparable baselines. A small or incomplete sample is a hypothesis, not a trend.

## One insight after research

The approved direction is synthesized from the supplied idea/source materials, which now include
collected documented findings, usable approved public facts and active Business Memory. Produce one
titled insight in Hebrew and/or English. Never invent facts, numbers, sources, client names or quotes.
Use public/anonymized confidentiality, remove private identifying details and state missing evidence.
All output remains draft for human review and approval.

Collected observations can inform topic/hook hypotheses, but collection never promotes their factual
assertions into `approved_facts`. Assertions intended for publication still need verification/approval
and the existing FactGate. Unused draft facts do not require blanket approval. Private groups, private
conversations and viewer identity analytics are outside this collection scope.

## Activation boundary

Version 2 references its exact profile in immutable prompt params:

```json
{
  "research_profile_key": "the_push.social_research",
  "research_profile_version": 1,
  "requires_collected_evidence": true,
  "topic_prompt_key": "research.topics.v0",
  "hook_prompt_key": "research.hooks.v0"
}
```

Offline planning may inspect the named draft explicitly. Online collection and v2 synthesis require
the matching profile and prompt to be approved/active by the human path. The profile body/key/version
are immutable; agent actors cannot approve or activate it. This migration grants neither activation
nor payment permission. The existing default-off paid-call controls remain separate.

## Distinct agents inside the CMK runtime

The runtime coordinator executes three bounded roles, rather than asking one unconstrained agent to
perform every step. Each role uses its own immutable Postgres prompt and returns a draft result:

| Runtime role | Prompt/version | Output |
|---|---|---|
| TopicResearchAgent | `research.topics.v0` v1 | `topics[]`, nonempty `coverage_notes[]`, draft status; pains/topics tied to collected source IDs |
| HookResearchAgent | `research.hooks.v0` v1 | `hook_examples[]`, optional original `recommended_angles[]`, coverage notes and draft status |
| ResearchSynthesisAgent | `research.v0` v2 | One HE/EN insight plus the integrated source-referenced research_report |

Topic/hook role outputs are analyses, not new evidence. The synthesis role rechecks their source IDs
against the original collection. The hook role may observe an opening only when its exact leading text
was captured as a full_post. Search snippets and imported excerpts can inspire candidate angles, but
cannot become verified openings or success evidence. `performance_claim` and model-generated metric
values are forbidden. No role can approve another role's facts/content, activate prompts, publish or
enable paid calls. Both new role prompts remain draft/inactive until reviewed by the human path.
