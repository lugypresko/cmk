# Focused multi-agent research in CMK

This is a runtime workflow inside CMK, not a team of coding assistants. Source collection is code;
three bounded research agents have separate prompts, inputs, durable task state and outputs.
They share Postgres Business Memory and the generation run's LLM budget.

| Runtime role | Input | Durable output |
|---|---|---|
| TopicResearchAgent | Focus profile, actual collected discussions, active brand/ICP | Source-referenced pains/topics + coverage notes |
| HookResearchAgent | Same evidence plus topic-agent findings | Observed openings when captured, mechanisms, original candidate hooks and limits |
| ResearchSynthesisAgent | Topic and hook results plus evidence | One titled HE/EN draft insight and a referenced research report |
| CoreCreator | Human-approved insight, research context and usable facts | Draft Core |
| Repurposer | Human-approved Core, report/hook guidance and format spec | Draft LinkedIn text or carousel |
| Evidence checks / SpecGate / FactGate | Source IDs, captured text, rules and facts | Deterministic block/pass findings |
| EditorialGuardian | Content + brand/ICP | Existing heuristic score, still uncalibrated |

Research calls are sequential because later roles consume earlier results. Each can be inspected via
`research_agent_tasks` and `llm_calls`. Completed results are reused on crash-resume; failed or unknown
paid calls do not auto-resend. One role failing stops this research work item without approving anything.
No assumption is made that different roles require different LLM models; the configured transport/model
is reused. Separate prompts and bounded responsibilities define the roles here.

## Scope lives in Postgres

Migration 015 stores the versioned The Push profile and draft research prompts. Focus clusters:
manager bottlenecks, engineering leadership/delegation, ownership/execution, AI engineering management,
AI Code Factory/verification/agent orchestration. Hebrew and English query pairs combine concrete topics
and managerial questions. Generic AI news, unrelated tool lists and pure coding tutorials are excluded.
The profile controls query count, sources and lookback. LinkedIn is primary; other public discussions
are secondary. A bounded search can leave platforms unqueried; coverage must never imply completeness.

The profile and prompts are proposals, not active production configuration. Before synthesis v2, Itay
reviews/activates the pinned profile and existing research.v0 version 2 plus research.topics.v0 and
research.hooks.v0. Core/Repurposer still need their own approved prompts. All output approvals remain
human-only. The same explicit human SQL actor convention as OPERATIONS.md applies.

## Public sources, not invented research

The optional Brave Web Search adapter discovers indexed public post/discussion excerpts. It does not
sign into LinkedIn or fetch private feeds. Search snippets are labelled search_snippet and are not
full posts or proof of the original opening. Provider page age may be published OR modified date;
it is stored separately and never substituted for a verified publication date. Index coverage and
recency are incomplete, so the report must state limits instead of claiming a platform-wide trend.

Imported documented public posts can supply full text, a publication date and observed engagement.
Each metric requires its own provenance URL and observation timestamp; unknown stays NULL. Imported
text and metrics are not independently verified just because they were imported. A captured opening
can be used as a hook example; likes/comments alone do not demonstrate conversion or causality.

All report topics/angles/examples must reference actual collected source_ids. The checker rejects
unknown IDs, model-generated numeric metrics and a claimed observed opening that does not match a
captured full-post first line. Snippets may inform original hook candidates, but cannot establish a
working/observed hook. Missing examples are left empty with coverage notes; counts are never padded.
These structural checks cannot verify factual or metric claims embedded in prose; human source review remains necessary.
Collected external claims remain research proposals, not approved_facts. FactGate still checks every
publishable claim, including claims with no fact_ids. No global approval of six unused site facts is needed.

## CLI: offline first

```bash
node scripts/cmk.mjs research-plan
node scripts/cmk.mjs research-import --file public-sources.json
node scripts/cmk.mjs research-status --id RESEARCH_RUN_UUID
node scripts/cmk.mjs start --research-id RESEARCH_RUN_UUID --idea 'Find the strongest The Push angle'
node scripts/cmk.mjs run --id WORK_UUID
node scripts/cmk.mjs research-agents --id WORK_UUID
```

Default planning and imports make zero search requests. The import file is a JSON array, for example:

```json
[{
  "url":"https://www.linkedin.com/posts/PUBLIC_POST",
  "public":true,
  "title":"Title from the actual source",
  "text":"Paste the actual captured source text here",
  "content_kind":"full_post",
  "published_at":null
}]
```

For observed metrics add `metrics:{comments:NUMBER,...}`, `metrics_observed_at:ISO_TIMESTAMP` and
`metrics_source:{kind:'manual_observation'|'public_platform_observation'|'platform_export',url:SOURCE_URL}`.
Do not fill unknown values. `full_post` must represent the whole captured post, not an excerpt.

Online search is a separate explicit decision from LLM payment. It requires all of:
`research-collect --allow-source-calls`, `CMK_RESEARCH_NETWORK_ENABLED=true`,
`CMK_RESEARCH_PAID_CALLS_ENABLED=true`, `CMK_RESEARCH_PROVIDER=brave`, `CMK_RESEARCH_API_KEY`,
`CMK_RESEARCH_RUN_BUDGET_USD` and `CMK_RESEARCH_USD_PER_REQUEST` set locally.
No price or key is supplied by the code. Search requests reserve configured costs durably before
transport. Unknown/failed calls retain the charge estimate; no automatic resend is attempted.
Reservations are local accounting, not a guarantee about provider-side billing. A crash may leave
reserved requests and incomplete evidence; investigate before explicitly starting another collection.

After sources and research prompts are ready, LLM invocation still needs the independent dual payment
opt-in in LLM_RUNTIME.md. Enabling LLM payment never authorizes search fees, and vice versa. A complete
research result stops at approve_insight; Core, derivative and package review remain separate human gates.

## Validation limits

Tests use injected search/model responses and isolated synthetic approvals. No live source-search
subscription or model was called, and no source claim, prompt or content was approved in the real DB.
The connector is implemented, but actual platform coverage and provider compatibility require explicit
live configuration/validation. Editorial semantic checking remains heuristic-stub-v0, not a calibrated LLM.
