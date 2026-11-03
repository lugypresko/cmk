import json
P="platform_limit_verify"; H="house_default"
def r(rule, sev="warn", src=H): return {"rule":rule,"severity":sev,"source":src}
COMMON=[r("Every number/claim maps to an approved+public fact in fact_ids (Guardian B-01).","block","guardian_rules"),
        r("No pricing, client names, testimonials or viewer data (B-02/B-03/B-04/B-12).","block","guardian_rules"),
        r("One closing question about the reader's own team/decision/process (CTA §8).","warn","guardian_rules")]
HE=[r("HE: >=60% Hebrew letters; plural/slash address (L-01..L-03). Adapt, don't translate.","block","guardian_rules")]
EN=[r("EN: zero Hebrew characters; one spelling system.","block","guardian_rules")]
specs=[
 # format, channel, active, stub, cols, structure, rules
 ("text_post","linkedin",True,False,dict(min_chars=600,max_chars=2200),
  [{"section":"hook","desc":"first 1-2 lines, works before 'see more'; first line <=120 chars"},
   {"section":"situation","desc":"evidence/scene first"},{"section":"pattern","desc":"name the working pattern, not a person's flaw"},
   {"section":"move","desc":"one reversible move"},{"section":"cta","desc":"closing question; optional P.S. soft offer"}],
  [r("Hard max 3,000 chars (B-11).","block",P),r("Paragraphs <=3 lines / <=350 chars."),r("Links go in first comment."),r("<=3 hashtags, <=3 emojis.")]),
 ("carousel","linkedin",True,False,dict(min_chars=150,max_chars=1300,max_slides=10,min_items=5,max_items=10,item_max_chars=300,aspect_ratio="4:5",requires_media=True,limits_verified=False),
  [{"section":"slide_1_hook","desc":"headline <=60 EN / <=50 HE"},{"section":"slides_2_to_n-1","desc":"one idea per slide; headline <=80, text <=300"},
   {"section":"last_slide_cta","desc":"CTA question = cta field"},{"section":"caption","desc":"body 150-1,300 chars, same language"}],
  [r("slides required, n sequential from 1 (B-11/F-C1).","block"),r("> max_slides blocks.","block"),r("HE: RTL render by PackageBuilder; no headline starting with an English token (F-C7).")]),
 ("x_thread","x",False,True,dict(min_items=3,max_items=8,item_max_chars=280),
  [{"section":"post_1_hook","desc":"stands alone; no 'thread 🧵' filler"},{"section":"posts_2_to_n-1","desc":"one point per post, numbered n/N optional"},
   {"section":"last_post_cta","desc":"closing question"}],
  [r("Each post <=280 chars (standard accounts).","block",P),r("No hashtags in post 1; <=1 overall."),r("Links only in last post.")]),
 ("broll","instagram",False,True,dict(min_duration_s=8,max_duration_s=20,min_items=3,max_items=8,aspect_ratio="9:16",requires_media=True),
  [{"section":"clips","desc":"3-8 clips: shot description, duration, on-screen text"},{"section":"overlay_hook","desc":"on-screen text in first 2s"},
   {"section":"caption","desc":"short caption with CTA question"}],
  [r("Every clip has source + license_note (own/stock/generated); no identifiable people without consent.","block"),
   r("On-screen text <=12 words per clip."),r("Captions/subtitles burned in or provided.")]),
 ("reel","instagram",False,True,dict(min_duration_s=20,max_duration_s=45,aspect_ratio="9:16",requires_media=True),
  [{"section":"hook_0_3s","desc":"spoken + on-screen hook"},{"section":"beats","desc":"3-5 beats: visual, voiceover, on-screen text, t_start/t_end"},
   {"section":"cta_beat","desc":"closing question"},{"section":"cover_text","desc":"<=6 words"},{"section":"caption","desc":"<=300 chars"}],
  [r("Platform max duration: verify current Instagram limit before enabling.","warn",P),r("Subtitles required (sound-off viewing)."),
   r("Beats contiguous, no gaps/overlaps; last t_end = duration_s.","block")]),
 ("short","youtube",False,True,dict(min_duration_s=20,max_duration_s=60,aspect_ratio="9:16",requires_media=True),
  [{"section":"title","desc":"<=70 chars, the claim or question"},{"section":"hook_0_3s","desc":"spoken + on-screen"},
   {"section":"beats","desc":"3-5 beats"},{"section":"cta_beat","desc":"question for comments"},{"section":"description","desc":"<=300 chars, link to site"}],
  [r("Platform max duration: verify current YouTube Shorts limit before enabling.","warn",P),r("Subtitles required."),
   r("Beats contiguous; last t_end = duration_s.","block")]),
 ("infographic","linkedin",False,True,dict(min_items=3,max_items=6,item_max_chars=160,aspect_ratio="4:5",requires_media=True),
  [{"section":"title","desc":"<=60 chars"},{"section":"panels","desc":"3-6 panels: heading + text; any number carries a fact_id"},
   {"section":"footer","desc":"source line for every public stat; brand mark"},{"section":"alt_text","desc":"full text alternative"},
   {"section":"caption","desc":"text_post rules, shorter (150-1,300)"}],
  [r("Every number on a panel has panels[].fact_id (B-01).","block"),r("alt_text required.","block"),r("No charts with invented data; data only from approved facts.","block")]),
 ("poll","linkedin",False,True,dict(min_items=2,max_items=4,item_max_chars=30,max_chars=140),
  [{"section":"question","desc":"<=140 chars, about the reader's own team/decision"},{"section":"options","desc":"2-4 options, <=30 chars, mutually exclusive"},
   {"section":"duration_days","desc":"1, 3, 7 or 14"},{"section":"intro_text","desc":"short context post"},{"section":"follow_up","desc":"planned result post (new piece, own Guardian pass)"}],
  [r("LinkedIn poll limits (question 140, options 2-4 x 30 chars).","block",P),r("No leading/loaded options; include a neutral option."),
   r("Results posts report only aggregate counts.","block")]),
 ("interactive_story","instagram",False,True,dict(min_items=3,max_items=7,item_max_chars=120,aspect_ratio="9:16",requires_media=True),
  [{"section":"frame_1_hook","desc":"text frame"},{"section":"interactive_frames","desc":"poll/quiz/question/slider stickers"},
   {"section":"reveal_frame","desc":"the pattern/insight"},{"section":"cta_frame","desc":"question sticker or link to site"}],
  [r(">=1 interactive frame; <=1 link frame."),r("Quiz 'correct' answers must be opinion-framed or fact-backed (B-01).","block"),
   r("Question-sticker replies are private; never repost a reply with identity.","block")]),
 ("email","email",False,True,dict(min_chars=400,max_chars=4000,item_max_chars=60),
  [{"section":"subject","desc":"<=60 chars"},{"section":"preheader","desc":"<=100 chars, complements subject"},
   {"section":"body","desc":"one idea: situation -> pattern -> move"},{"section":"cta","desc":"one reply-question or one link"},
   {"section":"footer","desc":"unsubscribe + sender identity (required)"}],
  [r("Only to opted-in list segments; unsubscribe footer required.","block"),r("No pricing/discounts (B-02).","block"),
   r("Sending is externally visible: Itay confirms each send.","block")]),
 ("avatar","linkedin",False,True,dict(min_duration_s=30,max_duration_s=90,aspect_ratio="9:16",requires_media=True),
  [{"section":"script","desc":"spoken script, ~130-150 words/min"},{"section":"on_screen_text","desc":"hook + key line"},
   {"section":"ai_disclosure","desc":"visible 'AI-generated' label + caption line"},{"section":"cta","desc":"closing question"}],
  [r("consent_ref must point to Itay's recorded consent for his likeness/voice.","block"),
   r("ai_disclosure required on video and caption.","block"),r("Script follows text_post voice rules; no claims beyond fact_ids.","block")]),
]
def q(v):
    if v is None: return "NULL"
    if isinstance(v,bool): return "true" if v else "false"
    if isinstance(v,int): return str(v)
    return "'"+str(v).replace("'","''")+"'"
cols=["min_chars","max_chars","max_slides","min_duration_s","max_duration_s","aspect_ratio","min_items","max_items","item_max_chars","requires_media","limits_verified"]
out=["""-- =============================================================================
-- CMK migration 003 — format_specs seeds for the 11 SPEC formats (HE + EN)
-- Requires 002_spec_formats.sql. Idempotent (ON CONFLICT DO NOTHING).
--
-- * text_post + carousel on LinkedIn: is_active = true, is_stub = false (v0 path).
-- * The other 9 formats: is_stub = true, is_active = false. Structure + rules only.
--   A stub can't be activated (CHECK format_specs_stub_inactive); Itay reviews,
--   sets is_stub=false, then is_active=true and format_registry.v0_enabled=true.
-- * Every rule has a source: 'guardian_rules' (existing doc), 'house_default'
--   (our starting choice, tune with data) or 'platform_limit_verify' (re-check
--   against the platform's current docs before enabling; limits_verified=false).
-- * No client facts, pricing or numbers about Itay's business are seeded here.
-- =============================================================================
BEGIN;
SET search_path = cmk, public;
SET LOCAL cmk.actor_type = 'human';   -- audit_log: seeds are applied by a human operator
SET LOCAL cmk.actor_name = 'migration_003';
"""]
for f,ch,active,stub,c,struct,rules in specs:
    for lang in ("en","he"):
        allrules=rules+COMMON+(HE if lang=="he" else EN)
        vals=[c.get(k) for k in cols]
        if c.get("requires_media") is None: vals[cols.index("requires_media")]=False
        if c.get("limits_verified") is None: vals[cols.index("limits_verified")]=False
        out.append(f"""INSERT INTO format_specs (format, channel, language, version, is_active, is_stub, {", ".join(cols)}, structure, rules, notes)
VALUES ('{f}', '{ch}', '{lang}', 1, {q(active)}, {q(stub)}, {", ".join(q(v) for v in vals)},
  {q(json.dumps(struct,ensure_ascii=False))}::jsonb,
  {q(json.dumps(allrules,ensure_ascii=False))}::jsonb,
  {q(("v0 active recipe." if active else "SPEC stub: structure only.")+" Primary channel; other channels in format_registry.default_channels get their own rows when enabled.")})
ON CONFLICT (format, channel, language, version) DO NOTHING;
""")
out.append("COMMIT;\n")
open("/workspace/cmk-memory-v0/migrations/003_format_specs_seed.sql","w").write("\n".join(out))
