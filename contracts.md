# CMK v0 — JSON Contracts

These are the shapes agents pass between steps. Each one maps 1:1 to `cmk.core_assets` and `cmk.content_library` in `schema.sql`.
JSON Schema draft 2020-12. Timestamps are ISO-8601 with an offset (they map to `timestamptz`). Scores are integers from 0 to 100.

## Shared enums

| Enum | Values | v0 active |
|---|---|---|
| `language` | `en`, `he` | both |
| `channel` | `linkedin`, `instagram`, `facebook`, `x`, `website` | `linkedin` |
| `format` | `text_post`, `carousel`, `thread`, `short_video_script`, `article` | `text_post`, `carousel` |
| `status` | `draft`, `in_review`, `needs_changes`, `approved`, `scheduled`, `published`, `rejected`, `archived` | all |

A CoreAsset can't be `scheduled` or `published`. Only a ContentPiece goes out.

## Guardian thresholds (v0 defaults, tune later)

- `brand_score` ≥ 75 **and** `icp_relevance_score` ≥ 70 → can go to `in_review` (a human approves)
- Any `blocker` finding (an unapproved fact, pricing, a client name, a confidentiality breach) → `needs_changes`, whatever the score
- `approved_by` must be a human. The DB rejects `approved|scheduled|published` rows that have no scores or no approver.

## GuardianReport (embedded)

```json
{
  "$id": "cmk/GuardianReport",
  "type": "object",
  "required": ["brand_score", "icp_relevance_score", "verdict", "findings", "checked_at"],
  "properties": {
    "brand_score":         { "type": "integer", "minimum": 0, "maximum": 100 },
    "icp_relevance_score": { "type": "integer", "minimum": 0, "maximum": 100 },
    "verdict":   { "enum": ["pass", "needs_changes", "reject"] },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["type", "severity", "message"],
        "properties": {
          "type":     { "enum": ["voice", "fact", "icp", "format", "confidentiality", "language", "cta", "other"] },
          "severity": { "enum": ["minor", "major", "blocker"] },
          "message":  { "type": "string" },
          "excerpt":  { "type": "string" },
          "suggestion": { "type": "string" }
        }
      }
    },
    "unsupported_claims": { "type": "array", "items": { "type": "string" } },
    "brand_voice_version": { "type": "integer" },
    "checked_at": { "type": "string", "format": "date-time" }
  }
}
```

## CoreAsset

```json
{
  "$id": "cmk/CoreAsset",
  "type": "object",
  "required": ["id", "title", "icp_profile_id", "brand_voice_id", "primary_language", "status"],
  "anyOf": [{ "required": ["body_en"] }, { "required": ["body_he"] }],
  "properties": {
    "id":               { "type": "string", "format": "uuid" },
    "core_insight_id":  { "type": ["string", "null"], "format": "uuid" },
    "brand_voice_id":   { "type": "string", "format": "uuid" },
    "icp_profile_id":   { "type": "string", "format": "uuid" },
    "title":            { "type": "string", "maxLength": 200 },
    "thesis_en":        { "type": ["string", "null"], "maxLength": 280 },
    "thesis_he":        { "type": ["string", "null"], "maxLength": 280 },
    "body_en":          { "type": ["string", "null"] },
    "body_he":          { "type": ["string", "null"] },
    "primary_language": { "enum": ["en", "he"] },
    "key_points": {
      "type": "array", "maxItems": 7,
      "items": { "type": "object", "properties": { "en": { "type": "string" }, "he": { "type": "string" } } }
    },
    "cta_en":           { "type": ["string", "null"] },
    "cta_he":           { "type": ["string", "null"] },
    "fact_ids":         { "type": "array", "items": { "type": "string", "format": "uuid" },
                          "description": "approved_facts relied on → content_fact_refs" },
    "status":           { "enum": ["draft", "in_review", "needs_changes", "approved", "rejected", "archived"] },
    "brand_score":         { "type": ["integer", "null"], "minimum": 0, "maximum": 100 },
    "icp_relevance_score": { "type": ["integer", "null"], "minimum": 0, "maximum": 100 },
    "guardian_report":  { "oneOf": [{ "$ref": "cmk/GuardianReport" }, { "type": "null" }] },
    "created_by":       { "enum": ["human", "agent"] },
    "approved_by":      { "type": ["string", "null"] },
    "approved_at":      { "type": ["string", "null"], "format": "date-time" },
    "created_at":       { "type": "string", "format": "date-time" },
    "updated_at":       { "type": "string", "format": "date-time" }
  }
}
```

## ContentPiece

```json
{
  "$id": "cmk/ContentPiece",
  "type": "object",
  "required": ["id", "core_asset_id", "format_spec_id", "format", "channel", "language", "body", "status"],
  "properties": {
    "id":             { "type": "string", "format": "uuid" },
    "core_asset_id":  { "type": "string", "format": "uuid" },
    "format_spec_id": { "type": "string", "format": "uuid" },
    "format":   { "enum": ["text_post", "carousel", "thread", "short_video_script", "article"] },
    "channel":  { "enum": ["linkedin", "instagram", "facebook", "x", "website"] },
    "language": { "enum": ["en", "he"] },
    "revision": { "type": "integer", "minimum": 1 },
    "parent_id": { "type": ["string", "null"], "format": "uuid" },
    "title":    { "type": ["string", "null"] },
    "hook":     { "type": ["string", "null"], "description": "first 1–2 lines" },
    "body":     { "type": "string" },
    "slides": {
      "type": ["array", "null"],
      "description": "required when format = carousel, otherwise null",
      "items": {
        "type": "object", "required": ["n", "headline"],
        "properties": { "n": { "type": "integer", "minimum": 1 }, "headline": { "type": "string" }, "text": { "type": "string" } }
      }
    },
    "cta":      { "type": ["string", "null"] },
    "hashtags": { "type": "array", "items": { "type": "string", "pattern": "^#\\S+$" }, "maxItems": 5 },
    "fact_ids": { "type": "array", "items": { "type": "string", "format": "uuid" } },
    "status":   { "enum": ["draft", "in_review", "needs_changes", "approved", "scheduled", "published", "rejected", "archived"] },
    "brand_score":         { "type": ["integer", "null"], "minimum": 0, "maximum": 100 },
    "icp_relevance_score": { "type": ["integer", "null"], "minimum": 0, "maximum": 100 },
    "guardian_report":  { "oneOf": [{ "$ref": "cmk/GuardianReport" }, { "type": "null" }] },
    "scheduled_at":     { "type": ["string", "null"], "format": "date-time" },
    "published_at":     { "type": ["string", "null"], "format": "date-time" },
    "external_post_id": { "type": ["string", "null"] },
    "external_url":     { "type": ["string", "null"], "format": "uri" },
    "rotation_slot":    { "type": ["integer", "null"], "minimum": 1, "maximum": 14, "description": "later: 14-day rotation" },
    "created_by":  { "enum": ["human", "agent"] },
    "approved_by": { "type": ["string", "null"] },
    "approved_at": { "type": ["string", "null"], "format": "date-time" }
  },
  "allOf": [
    { "if": { "properties": { "format": { "const": "carousel" } } }, "then": { "required": ["slides"] } },
    { "if": { "properties": { "status": { "enum": ["approved", "scheduled", "published"] } } },
      "then": { "required": ["brand_score", "icp_relevance_score", "approved_by", "approved_at"] } },
    { "if": { "properties": { "status": { "const": "scheduled" } } }, "then": { "required": ["scheduled_at"] } },
    { "if": { "properties": { "status": { "const": "published" } } }, "then": { "required": ["published_at"] } }
  ]
}
```

## Status flow

```
draft → (Guardian) → in_review → (Itay) → approved → scheduled → published
          ↘ needs_changes → draft (new revision; each edit → correction_log)
in_review → rejected | archived
```

## GuardianReport: clarifications (v0, added with guardian_rules.md)

These are optional fields. The schema above doesn't forbid extra properties, so v0 needs no migration.
- `findings[].check_id`: id from `guardian_checklist.json` (e.g. `B-01`, `CTA-02`). `findings[].field`: the field that was checked (`body`, `slides[3].text`, `fact_ids`). `findings[].points_delta`: the penalty that was applied, if any.
- Severity mapping: checklist `block` → finding `blocker`. Checklist `warn` → `major` or `minor` (set per check).
- `score_breakdown`: `{ "brand": {"BR-1": 12, …}, "icp": {"ICP-1": 30, …} }`. The components sum to the score before penalties and clamping.
- `unsupported_claims`: the exact text spans that tripped B-01 or C-05. It's empty when no claim tripped them.
- `checklist_version`: integer, `guardian_checklist.json` `version`.
- `recommend_reject`: boolean. It's true when verdict = `reject`. The status still becomes `needs_changes`, and only a human sets `rejected`.
- Verdict → status: `pass` → `in_review`; `needs_changes` → `needs_changes`; `reject` → `needs_changes` with `recommend_reject=true`.
- Score cap: when any blocker fires, `brand_score` ≤ 74. `icp_relevance_score` is not capped.
- Guardian writes `correction_log` rows (`corrected_by='agent'`) for every blocker and major finding, and sets `rule_candidate` when it can generalize the finding.

---

# v1 additions: SPEC formats (requires `migrations/002_spec_formats.sql`)

Everything above still holds. v1 only adds to it. The `text_post` and `carousel` contracts don't change, so the run 001 approved pieces stay valid.

## Shared enums (v1)

| Enum | Values | Enabled now (`format_registry.v0_enabled`) |
|---|---|---|
| `format` (SPEC, 11) | `text_post`, `carousel`, `x_thread`, `broll`, `reel`, `short`, `infographic`, `poll`, `interactive_story`, `email`, `avatar` | `text_post`, `carousel` |
| `format` (legacy v0, no generation) | `thread` → use `x_thread`; `short_video_script` → use `reel`/`short`; `article` (not in SPEC list) | none |
| `channel` | `linkedin`, `instagram`, `facebook`, `x`, `website`, `youtube`, `email` | `linkedin` |

The DB enforces three things:
- `content_library_payload_required`: the 9 new formats need a `payload` that has the required keys.
- `content_library_format_enabled` trigger: a piece can't reach `approved|scheduled|published` while its format has `v0_enabled = false`.
- `format_specs_stub_inactive`: a stub recipe can't be active.

## ContentPiece v1: extra properties

These go on top of `cmk/ContentPiece`. `body` stays required for every format. For the new formats it holds the **caption / post text / plain-text fallback** that Guardian scans in full.

```json
{
  "$id": "cmk/ContentPiece.v1",
  "properties": {
    "format":  { "enum": ["text_post","carousel","x_thread","broll","reel","short","infographic","poll","interactive_story","email","avatar"] },
    "channel": { "enum": ["linkedin","instagram","facebook","x","website","youtube","email"] },
    "payload": { "type": ["object","null"], "description": "format-specific, see below; null for text_post/carousel" },
    "media_refs": {
      "type": ["array","null"],
      "items": { "type": "object", "required": ["kind"],
        "properties": {
          "kind": { "enum": ["image","video","audio","pdf","subtitle"] },
          "path": { "type": "string" }, "url": { "type": "string", "format": "uri" },
          "alt_text": { "type": "string" },
          "source": { "enum": ["own","stock","generated","screen_capture"] },
          "license_note": { "type": "string" } } }
    },
    "prompt_version_id": { "type": ["string","null"], "format": "uuid" },
    "rotation_plan_id":  { "type": ["string","null"], "format": "uuid" },
    "rotation_slot_id":  { "type": ["string","null"], "format": "uuid" },
    "rotation_slot":     { "type": ["integer","null"], "minimum": 1, "maximum": 14, "description": "day in the 14-day plan" },
    "is_evergreen":      { "type": "boolean", "description": "human-set; allows recycling" },
    "recycled_from_id":  { "type": ["string","null"], "format": "uuid" },
    "guardian_threshold_profile": { "type": ["string","null"], "description": "e.g. v0, spec_v1" },
    "brand_score_float":         { "type": ["number","null"], "minimum": 0, "maximum": 1, "readOnly": true },
    "icp_relevance_score_float": { "type": ["number","null"], "minimum": 0, "maximum": 1, "readOnly": true }
  },
  "allOf": [
    { "$ref": "cmk/ContentPiece" },
    { "if": { "properties": { "format": { "const": "x_thread" } } },          "then": { "properties": { "payload": { "$ref": "cmk/payload/XThread" } },         "required": ["payload"] } },
    { "if": { "properties": { "format": { "const": "broll" } } },             "then": { "properties": { "payload": { "$ref": "cmk/payload/Broll" } },           "required": ["payload","media_refs"] } },
    { "if": { "properties": { "format": { "const": "reel" } } },              "then": { "properties": { "payload": { "$ref": "cmk/payload/Reel" } },            "required": ["payload"] } },
    { "if": { "properties": { "format": { "const": "short" } } },             "then": { "properties": { "payload": { "$ref": "cmk/payload/Short" } },           "required": ["payload"] } },
    { "if": { "properties": { "format": { "const": "infographic" } } },       "then": { "properties": { "payload": { "$ref": "cmk/payload/Infographic" } },     "required": ["payload"] } },
    { "if": { "properties": { "format": { "const": "poll" } } },              "then": { "properties": { "payload": { "$ref": "cmk/payload/Poll" } },            "required": ["payload"] } },
    { "if": { "properties": { "format": { "const": "interactive_story" } } }, "then": { "properties": { "payload": { "$ref": "cmk/payload/InteractiveStory" } },"required": ["payload"] } },
    { "if": { "properties": { "format": { "const": "email" } } },             "then": { "properties": { "payload": { "$ref": "cmk/payload/Email" } },           "required": ["payload"] } },
    { "if": { "properties": { "format": { "const": "avatar" } } },            "then": { "properties": { "payload": { "$ref": "cmk/payload/Avatar" } },          "required": ["payload"] } }
  ]
}
```

Every text field inside `payload` gets checked against the same claim, language and confidentiality rules as `body`. Guardian concatenates them in schema order. Any number anywhere needs a `fact_ids` entry, or a per-item `fact_id` where the schema has one.

### Shared building block: `Beat` (reel, short, avatar)

```json
{ "$id": "cmk/payload/Beat", "type": "object",
  "required": ["n","t_start","t_end"],
  "properties": {
    "n": { "type": "integer", "minimum": 1 },
    "t_start": { "type": "number", "minimum": 0 }, "t_end": { "type": "number", "exclusiveMinimum": 0 },
    "visual": { "type": "string", "description": "what is on screen" },
    "voiceover": { "type": "string" },
    "on_screen_text": { "type": "string", "maxLength": 80 },
    "fact_id": { "type": ["string","null"], "format": "uuid" } } }
```

The rule here is that beats are contiguous: `beats[0].t_start = 0`, each `t_start` equals the previous `t_end`, and the last `t_end` equals `duration_s`. Guardian enforces it as F-V1, a blocker.

### XThread (`x_thread`)
```json
{ "$id": "cmk/payload/XThread", "type": "object", "required": ["posts"],
  "properties": {
    "posts": { "type": "array", "minItems": 3, "maxItems": 8,
      "items": { "type": "object", "required": ["n","text"],
        "properties": { "n": { "type": "integer", "minimum": 1 }, "text": { "type": "string", "maxLength": 280 },
                        "media_ref": { "type": ["integer","null"], "description": "index into media_refs" } } } } } }
```
`body` is post 1 verbatim. `cta` is the last post's closing question.

### Broll (`broll`)
```json
{ "$id": "cmk/payload/Broll", "type": "object", "required": ["clips","total_duration_s"],
  "properties": {
    "total_duration_s": { "type": "number", "minimum": 1 },
    "clips": { "type": "array", "minItems": 3, "maxItems": 8,
      "items": { "type": "object", "required": ["n","duration_s","shot","source","license_note"],
        "properties": {
          "n": { "type": "integer", "minimum": 1 }, "duration_s": { "type": "number", "exclusiveMinimum": 0 },
          "shot": { "type": "string", "description": "shot description / prompt" },
          "on_screen_text": { "type": "string", "maxLength": 80 },
          "source": { "enum": ["own","stock","generated","screen_capture"] },
          "license_note": { "type": "string" },
          "media_ref": { "type": ["integer","null"] } } } },
    "voiceover": { "type": ["string","null"] },
    "audio_note": { "type": ["string","null"], "description": "track + license" } } }
```
`sum(clips.duration_s) = total_duration_s`. Identifiable people need consent, or the piece gets B-05.

### Reel (`reel`) / Short (`short`)
```json
{ "$id": "cmk/payload/Reel", "type": "object", "required": ["duration_s","beats"],
  "properties": {
    "duration_s": { "type": "number", "minimum": 1 },
    "beats": { "type": "array", "minItems": 2, "items": { "$ref": "cmk/payload/Beat" } },
    "cover_text": { "type": "string", "maxLength": 40 },
    "subtitles": { "enum": ["burned_in","srt_file"], "default": "burned_in" },
    "audio_note": { "type": ["string","null"] } } }

{ "$id": "cmk/payload/Short", "allOf": [{ "$ref": "cmk/payload/Reel" }], "required": ["duration_s","beats","title"],
  "properties": { "title": { "type": "string", "maxLength": 70 }, "description": { "type": "string", "maxLength": 300 } } }
```

### Infographic (`infographic`)
```json
{ "$id": "cmk/payload/Infographic", "type": "object", "required": ["title","panels","alt_text"],
  "properties": {
    "title": { "type": "string", "maxLength": 60 },
    "layout": { "enum": ["vertical_steps","grid","comparison","flow"] },
    "panels": { "type": "array", "minItems": 3, "maxItems": 6,
      "items": { "type": "object", "required": ["n","heading"],
        "properties": { "n": { "type": "integer", "minimum": 1 }, "heading": { "type": "string", "maxLength": 60 },
                        "text": { "type": "string", "maxLength": 160 },
                        "fact_id": { "type": ["string","null"], "format": "uuid", "description": "required if the panel has a number" } } } },
    "footer_sources": { "type": "array", "items": { "type": "string", "format": "uri" } },
    "alt_text": { "type": "string", "minLength": 20 } } }
```

### Poll (`poll`)
```json
{ "$id": "cmk/payload/Poll", "type": "object", "required": ["question","options","duration_days"],
  "properties": {
    "question": { "type": "string", "maxLength": 140 },
    "options": { "type": "array", "minItems": 2, "maxItems": 4, "uniqueItems": true, "items": { "type": "string", "maxLength": 30 } },
    "duration_days": { "enum": [1, 3, 7, 14] },
    "follow_up_plan": { "type": ["string","null"], "description": "results post; becomes its own piece" } } }
```
`body` is the intro text. Results posts report aggregate counts only and never name voters (B-12).

### InteractiveStory (`interactive_story`)
```json
{ "$id": "cmk/payload/InteractiveStory", "type": "object", "required": ["frames"],
  "properties": {
    "frames": { "type": "array", "minItems": 3, "maxItems": 7,
      "items": { "type": "object", "required": ["n","type","text"],
        "properties": {
          "n": { "type": "integer", "minimum": 1 },
          "type": { "enum": ["text","poll","quiz","question","slider","link"] },
          "text": { "type": "string", "maxLength": 120 },
          "options": { "type": "array", "maxItems": 4, "items": { "type": "string", "maxLength": 30 } },
          "correct_option": { "type": ["integer","null"], "description": "quiz only; must be fact-backed or opinion-framed" },
          "link_url": { "type": ["string","null"], "format": "uri" },
          "media_ref": { "type": ["integer","null"] } } } } } }
```
At least one frame must be interactive (`poll|quiz|question|slider`), and at most one can be `link`.

### Email (`email`)
```json
{ "$id": "cmk/payload/Email", "type": "object", "required": ["subject","preheader","body_markdown"],
  "properties": {
    "subject": { "type": "string", "maxLength": 60 },
    "preheader": { "type": "string", "maxLength": 100 },
    "body_markdown": { "type": "string" },
    "cta_label": { "type": ["string","null"] }, "cta_url": { "type": ["string","null"], "format": "uri" },
    "list_segment": { "type": ["string","null"], "description": "opted-in segment id; null until a list exists" },
    "reply_question": { "type": ["string","null"] } } }
```
`body` is the plain-text version. The unsubscribe footer and sender identity get added by the sending platform; they're never generated. Every send is externally visible, so Itay confirms it.

### Avatar (`avatar`)
```json
{ "$id": "cmk/payload/Avatar", "type": "object",
  "required": ["script","duration_s","avatar_profile_ref","consent_ref","ai_disclosure"],
  "properties": {
    "script": { "type": "string" },
    "duration_s": { "type": "number", "minimum": 1 },
    "beats": { "type": "array", "items": { "$ref": "cmk/payload/Beat" } },
    "avatar_profile_ref": { "type": "string", "description": "id in the avatar tool; no provider chosen yet" },
    "voice_profile_ref": { "type": ["string","null"] },
    "consent_ref": { "type": "string", "description": "approved_facts.fact_key of category 'boundary' recording Itay's consent for likeness/voice use" },
    "ai_disclosure": { "type": "string", "minLength": 1, "description": "label shown on video + caption, e.g. 'AI-generated avatar'" } } }
```
Guardian blocks (B-13, proposed) when `consent_ref` doesn't resolve to an approved fact, or when `ai_disclosure` is missing from the caption. The consent fact isn't seeded. Only Itay can create it.

## GuardianReport v1: optional fields
- `score_scale`: `"pct_0_100"` (the default and canonical scale) or `"float_0_1"`. See `guardian_thresholds.md`.
- `brand_score_float`, `icp_relevance_score_float`: numbers from 0 to 1, always equal to integer/100. They're read-only mirrors.
- `threshold_profile`: `"v0"` or `"spec_v1"`, whichever profile the verdict used.
- `prompt_version_id`: the Guardian prompt/rules version that produced the report.

## RotationPlan / RotationSlot / ScheduleProposal
```json
{ "$id": "cmk/RotationPlan", "type": "object", "required": ["id","start_date","days","timezone","daily_caps","status"],
  "properties": {
    "id": { "type": "string", "format": "uuid" }, "name": { "type": "string" },
    "start_date": { "type": "string", "format": "date" }, "days": { "type": "integer", "minimum": 1, "maximum": 14 },
    "timezone": { "const": "Asia/Jerusalem" },
    "daily_caps": { "type": "object", "additionalProperties": { "type": "integer", "minimum": 0 } },
    "constraints": { "type": "object" },
    "status": { "enum": ["draft","proposed","approved","active","completed","cancelled"] },
    "approved_by": { "type": ["string","null"] }, "approved_at": { "type": ["string","null"], "format": "date-time" },
    "slots": { "type": "array", "items": { "$ref": "cmk/RotationSlot" } } } }

{ "$id": "cmk/RotationSlot", "type": "object", "required": ["day","slot_index","channel","status"],
  "properties": {
    "day": { "type": "integer", "minimum": 1, "maximum": 14 }, "slot_index": { "type": "integer", "minimum": 1 },
    "channel": { "type": "string" }, "format": { "type": ["string","null"] }, "language": { "enum": ["en","he",null] },
    "local_time": { "type": ["string","null"], "pattern": "^\\d{2}:\\d{2}$" },
    "content_id": { "type": ["string","null"], "format": "uuid" },
    "status": { "enum": ["open","filled","confirmed","published","skipped"] },
    "rationale": { "type": "string" },
    "confirmed_by": { "type": ["string","null"] } } }
```
The v0 `ScheduleProposal` (`{content_id, proposed_at, rationale}`) is a single-slot RotationSlot.

## PromptVersion / AuditEntry
```json
{ "$id": "cmk/PromptVersion", "type": "object", "required": ["agent","prompt_key","version","body","status"],
  "properties": { "agent": { "type": "string" }, "prompt_key": { "type": "string", "pattern": "^[a-z0-9_.]+$" },
    "version": { "type": "integer", "minimum": 1 }, "format": { "type": ["string","null"] }, "language": { "enum": ["en","he",null] },
    "body": { "type": "string" }, "params": { "type": "object" }, "checksum": { "type": "string", "readOnly": true },
    "status": { "enum": ["draft","approved","retired"] }, "is_active": { "type": "boolean" },
    "change_note": { "type": "string" }, "correction_ids": { "type": "array", "items": { "type": "string", "format": "uuid" } } } }

{ "$id": "cmk/AuditEntry", "type": "object", "readOnly": true,
  "properties": { "id": { "type": "integer" }, "occurred_at": { "type": "string", "format": "date-time" },
    "actor_type": { "enum": ["human","agent"] }, "actor_name": { "type": ["string","null"] },
    "action": { "type": "string" }, "table_name": { "type": "string" }, "row_id": { "type": ["string","null"] },
    "old_status": { "type": ["string","null"] }, "new_status": { "type": ["string","null"] },
    "changes": { "type": ["object","null"] }, "run_id": { "type": ["string","null"] } } }
```
Agents never write `audit_log` directly. Triggers fill it in. Before each write, the runner sets `SET LOCAL cmk.actor_type / cmk.actor_name / cmk.run_id`. A missing context gets logged as `agent`.

---

# v2 additions: critique alignment (decisions locked 2026-11-03; requires `migrations/005_critique_alignment.sql`, not yet applied)

## GuardianReport v2 (D1)
These sit on top of GuardianReport v0/v1. The existing top-level fields (`verdict`, `brand_score`, `icp_relevance_score`, `findings`, `unsupported_claims`, `threshold_profile`) stay, and they're **derived** from the sub-reports.
```json
{ "$id": "cmk/GuardianReport.v2", "type": "object", "required": ["spec","fact","editorial","verdict"],
  "properties": {
    "spec":      { "type": "object", "required": ["pass","findings"], "description": "SpecGate (code). Blocks.",
                   "properties": { "pass": {"type":"boolean"}, "findings": {"type":"array"}, "checklist_version": {"type":"integer"} } },
    "fact":      { "type": "object", "required": ["pass","claims"], "description": "FactGate (code). Blocks.",
                   "properties": { "pass": {"type":"boolean"},
                     "claims": { "type":"array", "items": { "type":"object", "required":["text","kind"],
                       "properties": { "text":{"type":"string"}, "kind":{"enum":["fact","experience","opinion"]},
                                       "fact_id":{"type":["string","null"]}, "status":{"enum":["matched","missing","expired","weaker_ok","stronger_fail"]} } } },
                     "findings": {"type":"array"} } },
    "editorial": { "type": "object", "required": ["brand_score","icp_relevance_score"], "description": "EditorialGuardian (LLM). Scores only.",
                   "properties": { "brand_score":{"type":"integer","minimum":0,"maximum":100},
                     "icp_relevance_score":{"type":"integer","minimum":0,"maximum":100},
                     "source_supports_wording": {"enum":["yes","partly","no","n_a"]},
                     "adds_value": {"type":"boolean"}, "misleading_risk": {"type":"string"},
                     "findings": {"type":"array"}, "recommend_reject": {"type":"boolean"} } },
    "verdict": { "enum": ["pass","needs_changes","reject"] } } }
```
Verdict rule: if `spec.pass=false` or `fact.pass=false`, the verdict is `needs_changes`, whatever the editorial scores say. Otherwise the active threshold profile is applied to `editorial.*` (guardian_rules §9). **Editorial can't turn a code-gate block into a pass.** For a carousel or any rendered format, `spec` also requires `media_assets.qa_status='pass'` for that revision.

## ContentPiece v2: approval tracking (D2, audit-only)
Read-only fields: `approved_content_hash` (sha256 at approval), `edited_after_approval` (bool), `edited_after_approval_at`. Edits don't revoke approval. They're flagged and audited.

## PublishInstance / PublishAttempt (D3)
```json
{ "$id": "cmk/PublishInstance", "type": "object",
  "required": ["id","content_id","content_revision","sent_content_hash","channel","account_ref","state"],
  "properties": {
    "id": {"type":"string","format":"uuid"}, "content_id": {"type":"string","format":"uuid"},
    "content_revision": {"type":"integer"}, "sent_content_hash": {"type":"string"},
    "rotation_slot_id": {"type":["string","null"],"format":"uuid"}, "channel": {"type":"string"},
    "account_ref": {"type":"string"}, "mode": {"enum":["manual","adapter"]},
    "state": {"enum":["queued","sending","confirmed","failed_retryable","failed_final","unknown","cancelled"]},
    "max_attempts": {"type":"integer","minimum":1,"maximum":5},
    "external_post_id": {"type":["string","null"]}, "external_url": {"type":["string","null"]},
    "confirmed_by": {"type":["string","null"]}, "escalated_at": {"type":["string","null"],"format":"date-time"},
    "resolved_by": {"type":["string","null"]}, "stop_reason": {"type":["string","null"]} } }

{ "$id": "cmk/PublishAttempt", "type": "object", "required": ["id","publish_instance_id","attempt_no"],
  "properties": {
    "id": {"type":"string","format":"uuid","description":"unique attempt id; provider idempotency key where supported"},
    "publish_instance_id": {"type":"string","format":"uuid"}, "attempt_no": {"type":"integer","minimum":1},
    "started_at": {"type":"string","format":"date-time"}, "finished_at": {"type":["string","null"],"format":"date-time"},
    "outcome": {"enum":["ok","error","timeout","unknown",null]},
    "error_class": {"enum":["auth","validation","rate_limit","provider_5xx","network","other",null]},
    "provider_response": {"type":["object","null"]}, "verified_via": {"enum":["provider_lookup","itay_manual",null]} } }
```
Rules: `timeout`/`unknown` → instance `unknown` → escalate to Itay. **There is never an automatic new attempt.** A known transient error → `failed_retryable` (retry ≤ `max_attempts`). Other errors → `failed_final`. Leaving `unknown`/`failed_final` is human-only. `outcome` is write-once.

## LeadThread (D5)
```json
{ "$id": "cmk/LeadThread", "type": "object", "required": ["id","owner","stage"],
  "properties": {
    "id": {"type":"string","format":"uuid"},
    "source_content_id": {"type":["string","null"],"format":"uuid"},
    "source_publish_instance_id": {"type":["string","null"],"format":"uuid"},
    "channel": {"type":["string","null"]}, "conversation_ref": {"type":["string","null"]},
    "owner": {"type":"string","default":"Itay"},
    "stage": {"enum":["suggested","new","replied","call_booked","proposal_sent","won","lost","nurture","not_a_fit"]},
    "next_action": {"type":["string","null"]}, "next_action_due": {"type":["string","null"],"format":"date-time"},
    "proposal_ref": {"type":["string","null"],"description":"human-only"},
    "proposal_status": {"enum":["none","drafting","sent","accepted","declined"],"description":"human-only"},
    "payment_status": {"enum":["none","pending","paid","n_a"],"description":"human-only; no amounts stored"},
    "confirmed_by": {"type":["string","null"]} } }
```
Agents read the **`cmk/LeadHandoff`** view (`lead_handoff_v`): id, source refs, channel, conversation_ref, owner, stage, next_action, next_action_due. It has no proposal or payment fields. Agents create only `stage='suggested'`.

## WorkItem (Orchestrator state machine)
```json
{ "$id": "cmk/WorkItem", "type": "object", "required": ["id","kind","step","state","owner"],
  "properties": {
    "id": {"type":"string","format":"uuid"},
    "kind": {"enum":["core","derivative","render","package","publish","measure","ops"]},
    "step": {"enum":["research","create_core","repurpose","spec_gate","fact_gate","editorial_review","human_approval",
                     "render","render_qa","package","schedule","publish","verify_publish","measure","lead_handoff","error_watch"]},
    "subject_table": {"type":["string","null"]}, "subject_id": {"type":["string","null"],"format":"uuid"},
    "parent_work_item_id": {"type":["string","null"],"format":"uuid"},
    "state": {"enum":["pending","running","awaiting_human","needs_changes","done","failed","stopped"]},
    "owner": {"type":"string"}, "attempt_count": {"type":"integer"}, "max_attempts": {"type":"integer"},
    "blocked_on": {"type":["string","null"]}, "stop_reason": {"type":["string","null"]},
    "lease_owner": {"type":["string","null"]}, "lease_until": {"type":["string","null"],"format":"date-time"} } }
```
Allowed transitions live in `work_transitions`. `awaiting_human → *` and reviving `failed`/`stopped` are human-only. Entering `running` increments `attempt_count`, and exceeding `max_attempts` is refused. One open item per (subject, step).

## MediaAsset (RenderQA)
`{id, content_id, content_revision, kind, storage_uri, sha256, bytes, width, height, duration_s, page_count, source, license_note, consent_fact_id, ai_disclosure, qa_status: pending|pass|fail, qa_report, qa_checked_at}`. Stock media needs a `license_note`. Generated media needs `ai_disclosure=true`.
