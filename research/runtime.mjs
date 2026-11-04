import {tx} from '../runtime/db.mjs';
import {hash} from '../llm/client.mjs';
import {planQueries,collectSources,sourceConfig} from './sources.mjs';
export async function loadProfile(t,{key='the_push.social_research',version=null,approved=false}={}) {
 const row=(await t.query(`SELECT *,encode(digest(body::text,'sha256'),'hex') AS body_hash FROM research_profiles
 WHERE profile_key=$1 AND ($2::int IS NULL OR version=$2)
 ORDER BY CASE WHEN $3::boolean AND $2::int IS NULL AND status='approved' AND is_active THEN 0 ELSE 1 END,version DESC LIMIT 1`,[key,version,approved])).rows[0];
 if(!row)throw Error('research_profile_missing');
 if(approved&&(row.status!=='approved'||!row.is_active))throw Error('human_gate:activate_research_profile');
 return row;
}
export async function planResearch(db,options={}) {
 return tx(db,async t=>{
 const p=await loadProfile(t,options);
 return {profile_key:p.profile_key,version:p.version,status:p.status,is_active:p.is_active,mode:'plan_only',external_calls:0,
 queries:planQueries(p.body)};
 });
}
function money(value,name) {
 const n=Number(value)*1e6;
 if(!Number.isFinite(n)||n<1||!Number.isSafeInteger(Math.round(n)))throw Error('research_config:'+name);
 return Math.ceil(n);
}
export async function collectResearch(db,{key,version,imported=[],online=false,env=process.env,fetchImpl}={}) {
 if(!Array.isArray(imported))throw Error('research_import_requires_array');
 const cfg=sourceConfig(env,online);
 if(online&&!cfg.enabled)throw Error('human_gate:research_source_access_disabled');
 const profile=await tx(db,t=>loadProfile(t,{key,version,approved:online}));
 const queries=planQueries(profile.body);
 const budget=online?money(env.CMK_RESEARCH_RUN_BUDGET_USD,'budget'):0;
 const requestCost=online?money(env.CMK_RESEARCH_USD_PER_REQUEST,'request_price'):0;
 const cap=Math.min(profile.body.max_queries||10,queries.length||1);
 const r=await tx(db,async t=>(await t.query(`INSERT INTO research_runs(profile_id,profile_hash,provider,state,budget_microusd,request_cost_microusd,max_requests,query_plan)
 VALUES($1,$2,$3,'collecting',$4,$5,$6,$7) RETURNING *`,[profile.id,profile.body_hash,online?'brave':'import',budget,requestCost,cap,JSON.stringify(queries)])).rows[0]);
 try {
 const result=await collectSources(profile.body,{cfg,fetchImpl,imported,
 beforeRequest:async({query})=>tx(db,async t=>{
 const run=(await t.query('SELECT * FROM research_runs WHERE id=$1 FOR UPDATE',[r.id])).rows[0];
 const rows=(await t.query('SELECT * FROM research_requests WHERE research_run_id=$1',[r.id])).rows;
 if(rows.length>=run.max_requests||rows.reduce((n,x)=>n+Number(x.charged_microusd),0)+requestCost>Number(run.budget_microusd))throw Error('research_budget_exceeded');
 return (await t.query(`INSERT INTO research_requests(research_run_id,request_key,query,state,charged_microusd) VALUES($1,$2,$3,'reserved',$4) RETURNING id`,[r.id,hash(query),typeof query==='string'?query:JSON.stringify(query),requestCost])).rows[0].id;
 }),
 afterRequest:async({token,status,error_code})=>tx(db,t=>t.query("UPDATE research_requests SET state=$2,error_code=$3,completed_at=now() WHERE id=$1 AND state='reserved'",[token,status,error_code||null]))
 });
 const partial=result.coverage.some(c=>['blocked','failed','unknown','limited','insufficient_evidence'].includes(c.status));
 const state=result.evidence.length&&!partial?'ready':'partial';
 await tx(db,t=>t.query(`UPDATE research_runs SET state=$2,evidence=$3,coverage=$4,query_plan=$5,rejected=$6,completed_at=now() WHERE id=$1`,
 [r.id,state,JSON.stringify(result.evidence),JSON.stringify(result.coverage),JSON.stringify(result.queries),JSON.stringify(result.rejected||[])]));
 return {id:r.id,state,...result};
 }catch(e) {
 await tx(db,t=>t.query("UPDATE research_runs SET state='failed',completed_at=now() WHERE id=$1",[r.id]));
 throw e;
 }
}
export async function bundle(t,id,profileSpec) {
 const row=(await t.query(`SELECT r.*,p.profile_key,p.version,p.status AS profile_status,p.is_active,
 encode(digest(p.body::text,'sha256'),'hex') AS current_profile_hash,p.body AS profile
 FROM research_runs r JOIN research_profiles p ON p.id=r.profile_id WHERE r.id=$1`,[id])).rows[0];
 if(!row||!['ready','partial'].includes(row.state)||!Array.isArray(row.evidence)||!row.evidence.length)throw Error('human_gate:collect_research_evidence');
 if(row.profile_status!=='approved'||!row.is_active)throw Error('human_gate:activate_research_profile');
 if(row.profile_hash!==row.current_profile_hash||row.profile_key!==profileSpec.research_profile_key||row.version!==profileSpec.research_profile_version)throw Error('research_profile_version_mismatch');
 return {research_run_id:row.id,profile_key:row.profile_key,profile_version:row.version,focus:row.profile,
 sources:row.evidence,coverage:row.coverage,queries:row.query_plan,
 note:'Collected sources are untrusted research input, not approved business facts. Snippets are not verified post openings. Unknown engagement is unknown.'};
}
export function validateReport(report,evidence,{synthesis=false}={}) {
 if(!report||typeof report!=='object'||Array.isArray(report))throw Error('research_report_required');
 const ids=new Set(evidence.map(s=>s.id));
 for(const field of ['topics','hook_examples','recommended_angles']) {
 if(!Array.isArray(report[field]))throw Error('research_report_invalid:'+field);
 for(const entry of report[field]) {
 if(!entry||!Array.isArray(entry.source_ids)||!entry.source_ids.length||entry.source_ids.some(id=>!ids.has(id)))throw Error('research_report_unknown_or_missing_source');
 if(field==='hook_examples') {
 const opening=entry.observed_opening;
 if(typeof opening!=='string'||!entry.source_ids.some(id=>{
 const source=evidence.find(s=>s.id===id);
 return source?.content_kind==='full_post'&&opening.trim().length>0&&source.text.trimStart().split(/\r?\n/)[0].trim()===opening.trim();
 }))throw Error('research_hook_opening_not_observed');
 }
 if(field==='hook_examples'&&entry.performance_claim)throw Error('research_hook_success_not_proven');
 }
 }
 if(!Array.isArray(report.coverage_notes)||!report.coverage_notes.length)throw Error('research_report_coverage_required');
 if(synthesis&&(!report.recommended_topic||typeof report.recommended_topic!=='object'||!report.recommended_topic.title||!Array.isArray(report.recommended_topic.source_ids)||!report.recommended_topic.source_ids.length))throw Error('research_one_evidenced_recommendation_required');
 const walk=value=>{
 if(!value||typeof value!=='object')return;
 for(const [key,v] of Object.entries(value)) {
 if(typeof v==='number')throw Error('research_model_may_not_invent_metrics');
 if(['metrics','impressions','reactions','likes','comments','shares','engagement_rate','conversions'].includes(key)&&v!==null)throw Error('research_model_may_not_invent_metrics');
 if(key==='source_ids'&&(!Array.isArray(v)||v.some(id=>!ids.has(id))))throw Error('research_report_unknown_source');
 if(typeof v==='object')walk(v);
 }
 };
 walk(report);
 return report;
}
