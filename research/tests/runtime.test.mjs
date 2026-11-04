import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {openDB,tx,root} from '../../runtime/db.mjs';
import {prepareJudgment} from '../../runtime/agents.mjs';
import {enqueue,run} from '../../runtime/orchestrator.mjs';
import {planResearch,collectResearch,validateReport,loadProfile} from '../runtime.mjs';
const human={type:'human',name:'TEST HUMAN',run:'research-integration'};
const env={CMK_LLM_PAID_CALLS_ENABLED:'true',CMK_LLM_API_BASE_URL:'https://provider.invalid/v1',CMK_LLM_MODEL:'mock-model',CMK_LLM_API_KEY:'MOCK-KEY',CMK_LLM_INPUT_USD_PER_MILLION:'1',CMK_LLM_OUTPUT_USD_PER_MILLION:'2',CMK_LLM_RUN_BUDGET_USD:'0.5'};
const sourceEnv={CMK_RESEARCH_PROVIDER:'brave',CMK_RESEARCH_NETWORK_ENABLED:'true',CMK_RESEARCH_PAID_CALLS_ENABLED:'true',CMK_RESEARCH_API_KEY:'MOCK-SOURCE-KEY',CMK_RESEARCH_RUN_BUDGET_USD:'0.000001',CMK_RESEARCH_USD_PER_REQUEST:'0.01'};
const raw={url:'https://www.linkedin.com/posts/test-review-bottleneck',public:true,content_kind:'full_post',title:'Engineering managers face a review bottleneck',
 text:'Your agents shipped more. Why do decisions still wait for you?\nCoding agents create a review bottleneck for engineering managers.',published_at:'2026-11-03T10:00:00Z',
 metrics:{comments:7},metrics_observed_at:'2026-11-04T09:00:00Z',metrics_source:{kind:'manual_observation',url:'https://www.linkedin.com/posts/test-review-bottleneck'}};
let db,collection;
before(async()=>{db=await openDB('memory://');for(const f of ['schema.sql',...fs.readdirSync(root+'migrations').filter(f=>/^\d+.*sql$/.test(f)).sort().map(f=>'migrations/'+f)])await db.exec(fs.readFileSync(root+f,'utf8'));});
after(async()=>{await db.close();});
test('draft profile can be planned/imported offline without approving it or making requests',async()=>{
 const plan=await planResearch(db);assert.equal(plan.external_calls,0);assert.equal(plan.status,'draft');assert.ok(plan.queries.length);
 let requests=0;collection=await collectResearch(db,{imported:[raw],fetchImpl:async()=>{requests++;throw Error('forbidden');}});
 assert.equal(requests,0);assert.equal(collection.external_calls,0);assert.equal(collection.evidence.length,1);
 assert.equal((await db.query("SELECT count(*)::int AS n FROM cmk.approved_facts WHERE status='approved'")).rows[0].n,0);
});
test('v2 synthesis requires active approved profile and collected evidence',async()=>{
 await tx(db,async t=>{await t.query("UPDATE prompt_versions SET is_active=false WHERE prompt_key='research.v0'");await t.query("UPDATE prompt_versions SET status='approved',is_active=true,approved_by='TEST HUMAN',approved_at=now() WHERE prompt_key='research.v0' AND version=2");},human);
 await assert.rejects(tx(db,t=>prepareJudgment(t,'research.v0',{idea:'test'})),/collect_research_evidence/);
 await assert.rejects(tx(db,t=>prepareJudgment(t,'research.v0',{idea:'test',research_run_id:collection.id})),/activate_research_profile/);
 await tx(db,t=>t.query("UPDATE research_profiles SET status='approved',is_active=true,approved_by='TEST HUMAN',approved_at=now()"),human);
 const p=await tx(db,t=>prepareJudgment(t,'research.v0',{idea:'test',research_run_id:collection.id}));
 assert.equal(p.input.research.sources[0].url,raw.url);assert.equal(p.memory.approved_facts.length,0);
 await tx(db,t=>t.query("INSERT INTO research_profiles(profile_key,version,body) SELECT profile_key,2,body FROM research_profiles WHERE version=1"));
 const active=await tx(db,t=>loadProfile(t,{approved:true}));assert.equal(active.version,1);
 const latest=await tx(db,t=>loadProfile(t));assert.equal(latest.version,2);
});
test('unapproved topic/hook roles stop before the first model charge',async()=>{
 let requests=0;
 const w=await enqueue(db,'core',{idea:'Focused research',research_run_id:collection.id});
 const r=await run(db,w.id,undefined,{allowPaid:true,env,fetchImpl:async()=>{requests++;throw Error('forbidden');}});
 assert.equal(requests,0);assert.equal(r.state,'needs_changes');assert.match(r.last_error,/activate_prompt:research.topics.v0/);
 assert.equal((await db.query('SELECT count(*)::int AS n FROM cmk.llm_calls')).rows[0].n,0);
});
test('three runtime agents use independent prompts, shared budget, evidence and upstream outputs',async()=>{
 await tx(db,t=>t.query("UPDATE prompt_versions SET status='approved',is_active=true,approved_by='TEST HUMAN',approved_at=now() WHERE prompt_key IN ('research.topics.v0','research.hooks.v0')"),human);
 const id=collection.evidence[0].id,opening=raw.text.split('\n')[0];
 const topics={status:'draft',topics:[{topic:'Review bottleneck',managerial_pain:'All decisions return to manager',source_ids:[id]}],coverage_notes:['One synthetic imported post, not a trend.']};
 const hooks={status:'draft',hook_examples:[{source_ids:[id],observed_opening:opening,mechanism:'Contrast output with waiting decisions'}],recommended_angles:[{angle:'Move repeat checks into gates',original_hooks:['What still waits for your approval?'],source_ids:[id]}],coverage_notes:['Imported engagement is not business impact.']};
 const report={topics:topics.topics,hook_examples:hooks.hook_examples,recommended_angles:hooks.recommended_angles,
 recommended_topic:{title:'Review bottlenecks',source_ids:[id],uncertainty:'One post only'},coverage_notes:['Metrics are imported observations; effectiveness unknown.']};
 const output={status:'draft',title:'תובנה מוצעת',insight_he:'לבחון איפה החלטות חוזרות למנהל.',confidentiality:'public',research_report:report};
 const seen=[],outputs=[topics,hooks,output];
 const w=await enqueue(db,'core',{idea:'Research The Push topics',research_run_id:collection.id});
 const r=await run(db,w.id,undefined,{allowPaid:true,env,fetchImpl:async(url,opt)=>{
 const body=JSON.parse(opt.body),input=JSON.parse(body.messages[1].content);seen.push(input);
 return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify(outputs[seen.length-1])}}],usage:{prompt_tokens:100,completion_tokens:100}}),{status:200});
 }});
 assert.equal(r.blocked_on,'human_gate:approve_insight');assert.equal(seen.length,3);
 assert.equal(seen[0].input.research_role,'topics');assert.deepEqual(seen[1].input.topic_agent,topics);
 assert.deepEqual(seen[2].input.hook_agent,hooks);assert.equal(seen[2].memory.approved_facts.length,0);
 const tasks=(await db.query('SELECT * FROM cmk.research_agent_tasks WHERE work_item_id=$1 ORDER BY started_at',[w.id])).rows;
 assert.equal(tasks.length,3);assert.ok(tasks.every(t=>t.state==='done'));assert.equal(new Set(tasks.map(t=>t.prompt_version_id)).size,3);
 const calls=(await db.query('SELECT * FROM cmk.llm_calls WHERE run_id=$1',[w.run_id])).rows;assert.equal(calls.length,3);
 const insight=(await db.query('SELECT * FROM cmk.core_insights WHERE id=$1',[r.context.insight_id])).rows[0];
 assert.equal(insight.status,'draft');assert.equal(insight.research_run_id,collection.id);assert.deepEqual(insight.research_report,report);
});
test('unknown source references, invented metrics and snippet openings cannot become research evidence',()=>{
 const id=collection.evidence[0].id;
 const base={topics:[],hook_examples:[],recommended_angles:[],coverage_notes:['No comparable baseline.']};
 assert.throws(()=>validateReport({...base,topics:[{source_ids:['made-up']}]},collection.evidence),/source/);
 assert.throws(()=>validateReport({...base,topics:[{source_ids:[id],likes:10000}]},collection.evidence),/invent_metrics/);
 assert.throws(()=>validateReport({...base,hook_examples:[{source_ids:[id],observed_opening:'Fake opening'}]},collection.evidence),/opening_not_observed/);
 assert.throws(()=>validateReport({...base,hook_examples:[{source_ids:[id],observed_opening:'Y'}]},collection.evidence),/opening_not_observed/);
 const snippets=collection.evidence.map(s=>({...s,content_kind:'search_snippet'}));
 assert.throws(()=>validateReport({...base,hook_examples:[{source_ids:[id],observed_opening:raw.text.split('\n')[0]}]},snippets),/opening_not_observed/);
});
test('online source budget is independent of model permission and checked before search',async()=>{
 let calls=0;
 await assert.rejects(collectResearch(db,{online:true,env,fetchImpl:async()=>{calls++;}}),/source_access_disabled/);
 const r=await collectResearch(db,{online:true,env:sourceEnv,fetchImpl:async()=>{calls++;throw Error('must not fetch');}});
 assert.equal(calls,0);assert.equal(r.external_calls,0);assert.equal(r.state,'partial');assert.ok(r.coverage.some(c=>c.status==='blocked'));
});
