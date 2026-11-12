import {spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {root} from './db.mjs';
import {bundle,validateReport} from '../research/runtime.mjs';
export function bridge(op,args) {
 const p=spawnSync(process.env.CMK_PYTHON||'python3',['-m','runtime.bridge'],{cwd:root,input:JSON.stringify({op,...args}),encoding:'utf8'});
 if(p.status!==0)throw Error(p.stderr||p.stdout);return JSON.parse(p.stdout);
}
export async function context(t) {
 const rows=async q=>(await t.query(q)).rows;
 return {checklist:(await rows('SELECT body FROM guardian_checklists ORDER BY version DESC LIMIT 1'))[0].body,
 format_specs:await rows('SELECT * FROM format_specs WHERE is_active'),
 brand_voice:(await rows('SELECT * FROM brand_voice WHERE is_active'))[0],
 icp:(await rows('SELECT * FROM icp_profiles WHERE is_active ORDER BY priority LIMIT 1'))[0],
 thresholds:(await rows('SELECT * FROM guardian_thresholds WHERE is_active'))[0]};
}
export const promptKeys={research:'research.v0',create_core:'core_creator.v0',repurpose:'repurposer.v0'};
const contracts={
 'research.v0':{required:['title','confidentiality'],properties:{title:'string',insight_he:'string|null',insight_en:'string|null',confidentiality:'public|anonymized',status:'draft'},note:'At least one insight language is required. No approvals.'},
 'core_creator.v0':{required:['title','primary_language'],properties:{title:'string (max 200)',primary_language:'he|en',body_he:'string|null',body_en:'string|null',thesis_he:'string|null (max 280)',thesis_en:'string|null (max 280)',cta_he:'string|null',cta_en:'string|null',key_points:'array of {he?: string, en?: string}, max 7',fact_ids:'array of allowed fact UUIDs',status:'draft'},note:'Include a body in the primary language; no IDs or approval fields. Only sourced factual claims.'},
 'repurposer.v0':{required:['body'],properties:{body:'string',hook:'string|null',cta:'string|null',hashtags:'array of hashtags, max 5',slides:'carousel only: array of {n: integer,headline: string,text?: string}',fact_ids:'array of allowed fact UUIDs',status:'draft'},note:'Use requested format and language. IDs and approval fields are assigned by the runtime.'}
};
export async function prepareJudgment(t,key,input) {
 if(!contracts[key])throw Error('unsupported generation step');
 const prompt=(await t.query("SELECT id,prompt_key,version,body,params FROM prompt_versions WHERE prompt_key=$1 AND is_active AND status='approved'",[key])).rows[0];
 if(!prompt)throw Error('human_gate:activate_prompt:'+key);
 const ctx=await context(t);
 const facts=(await t.query("SELECT id,fact_key,statement_he,statement_en,source_url,source_note FROM usable_facts_v WHERE 'public_posts'=ANY(usage_scope) ORDER BY fact_key")).rows;
 let source;
 if(key==='research.v0') {
  if(!input.idea?.trim()&&!input.source_notes?.trim())throw Error('idea_or_source_notes_required');
  source={idea:input.idea||null,source_notes:input.source_notes||null,goal:input.goal||null,language:input.language||'he'};
  if(prompt.params.requires_collected_evidence){
   if(!input.research_run_id)throw Error('human_gate:collect_research_evidence');
   source.research=await bundle(t,input.research_run_id,prompt.params);
  }
 }else if(key==='core_creator.v0') {
  const insight=(await t.query("SELECT id,title,insight_he,insight_en,confidentiality,research_run_id,research_report FROM core_insights WHERE id=$1 AND status='approved' AND confidentiality<>'private'",[input.insight_id])).rows[0];
  if(!insight)throw Error('human_gate:approve_insight');
  source={insight,language:input.language||'he',goal:input.goal||null};
  if(insight.research_run_id){const r=(await t.query('SELECT evidence,coverage FROM research_runs WHERE id=$1',[insight.research_run_id])).rows[0];source.research_guidance={report:insight.research_report,...r};}
 }else {
  const core=(await t.query("SELECT id,core_insight_id,title,body_he,body_en,thesis_he,thesis_en,key_points,cta_he,cta_en,primary_language FROM core_assets WHERE id=$1 AND status='approved'",[input.core_id])).rows[0];
  if(!core)throw Error('human_gate:approve_core');
  core.fact_ids=(await t.query('SELECT approved_fact_id FROM content_fact_refs WHERE core_asset_id=$1 ORDER BY approved_fact_id',[core.id])).rows.map(r=>r.approved_fact_id);
  if(!['he','en'].includes(input.language)||!['text_post','carousel'].includes(input.format))throw Error('unsupported v0 derivative');
  const spec=ctx.format_specs.find(s=>s.format===input.format&&s.language===input.language&&s.channel==='linkedin');
  if(!spec||spec.is_stub)throw Error('active_format_spec_required');
  source={core,format:input.format,language:input.language,format_spec:spec};
  if(core.core_insight_id){const i=(await t.query('SELECT research_report,research_run_id FROM core_insights WHERE id=$1',[core.core_insight_id])).rows[0];if(i?.research_run_id){const r=(await t.query('SELECT evidence,coverage FROM research_runs WHERE id=$1',[i.research_run_id])).rows[0];source.research_guidance={report:i.research_report,...r};}}
 }
 return {prompt,input:source,memory:{brand_voice:ctx.brand_voice,icp:ctx.icp,approved_facts:facts},output_contract:key==='research.v0'&&prompt.params.requires_collected_evidence?{...contracts[key],research_report:{topics:'array of source-referenced topics',hook_examples:'array of verified opening examples or empty',recommended_angles:'array of source-referenced angles and original candidate hooks',recommended_topic:'{title,source_ids,uncertainty}: one selected direction',coverage_notes:'nonempty array of missing evidence/access limits'}}:contracts[key]};
}
async function judgment(t,key,input,{provider,fixture}={}) {
 if(fixture) return structuredClone(fixture); // Explicit existing test/fixture mode remains offline.
 if(!provider)throw Error('human_gate:llm_provider_required');
 return provider(await prepareJudgment(t,key,input));
}

async function insertDraft(t,table,row,cols) {
 const selected=cols.filter(k=>row[k]!==undefined);
 const vals=selected.map(k=>['key_points','slides','payload','media_refs','research_report'].includes(k)&&row[k]!==null?JSON.stringify(row[k]):row[k]);
 await t.query(`INSERT INTO ${table}(${selected.join(',')}) VALUES(${selected.map((_,i)=>'$'+(i+1)).join(',')})`,vals);
 return row;
}
export async function research(t,input,options) {
 const r=await judgment(t,'research.v0',input,options);
 if(!r.title||!['public','anonymized'].includes(r.confidentiality)||!(r.insight_he||r.insight_en))throw Error('Research output invalid/private');
 if(r.status&&r.status!=='draft'||r.approved_by||r.approved_at)throw Error('Research cannot approve');
 const row={id:randomUUID(),title:r.title,insight_he:r.insight_he,insight_en:r.insight_en,
  confidentiality:r.confidentiality,origin:'other',status:'draft',created_by:'agent'};
 if(input.research_run_id&&!options?.fixture){
 const prepared=await prepareJudgment(t,'research.v0',input);
 if(prepared.prompt.params.requires_collected_evidence){
 row.research_run_id=input.research_run_id;row.research_report=validateReport(r.research_report,prepared.input.research.sources,{synthesis:true});
 }
 }
 return insertDraft(t,'core_insights',row,Object.keys(row));
}
export async function createCore(t,input,options) {
 if(input.insight_id) {
 const insight=(await t.query('SELECT * FROM core_insights WHERE id=$1',[input.insight_id])).rows[0];
 if(!insight||insight.status!=='approved'||insight.confidentiality==='private')throw Error('human_gate:approve_insight');
 }
 const r=await judgment(t,'core_creator.v0',input,options);
 if((r.status&&r.status!=='draft')||r.approved_by||r.approved_at)throw Error('Agent output must be draft');
 const ctx=await context(t);
 const row={...r,id:randomUUID(),brand_voice_id:ctx.brand_voice.id,icp_profile_id:ctx.icp.id,
 core_insight_id:input.insight_id||null,status:'draft',created_by:'agent'};
 bridge('validate',{contract:'cmk/CoreAsset',row});
 await insertDraft(t,'core_assets',row,['id','brand_voice_id','icp_profile_id','core_insight_id','title','primary_language','body_en','body_he','thesis_en','thesis_he','key_points','cta_en','cta_he','status','created_by']);
 await factRefs(t,'core_asset_id',row);
 return row;
}
async function factRefs(t,col,row) {
 for(const fid of row.fact_ids||[]) {
 if(!(await t.query("SELECT 1 FROM usable_facts_v WHERE id=$1 AND 'public_posts'=ANY(usage_scope)",[fid])).rows.length)throw Error('human_gate:approve_used_fact:'+fid);
 await t.query(`INSERT INTO content_fact_refs(${col},approved_fact_id) VALUES($1,$2)`,[row.id,fid]);
 }
}
export async function repurpose(t,input,options) {
 const core=(await t.query('SELECT * FROM core_assets WHERE id=$1',[input.core_id])).rows[0];
 if(core?.status!=='approved')throw Error('human_gate:approve_core');
 if(!['text_post','carousel'].includes(input.format)||!['he','en'].includes(input.language))throw Error('Unsupported v0 derivative');
 const r=await judgment(t,'repurposer.v0',{...input,core},options);
 if((r.status&&r.status!=='draft')||r.approved_by||r.approved_at)throw Error('Agent output must be draft');
 const spec=(await t.query("SELECT id FROM format_specs WHERE format=$1 AND language=$2 AND channel='linkedin' AND is_active AND NOT is_stub",[input.format,input.language])).rows[0];
 const rev=(await t.query("SELECT coalesce(max(revision),0)+1 AS n FROM content_library WHERE core_asset_id=$1 AND format=$2 AND language=$3 AND channel='linkedin'",[core.id,input.format,input.language])).rows[0].n;
 const row={...r,id:randomUUID(),core_asset_id:core.id,format_spec_id:spec.id,format:input.format,channel:'linkedin',language:input.language,revision:rev,status:'draft',created_by:'agent'};
 bridge('validate',{contract:'cmk/ContentPiece',row});
 await insertDraft(t,'content_library',row,['id','core_asset_id','format_spec_id','format','channel','language','revision','title','hook','body','slides','cta','hashtags','payload','media_refs','status','created_by']);
 await factRefs(t,'content_id',row);
 return row;
}
export async function guardian(t,table,id,{readOnly=false}={}) {
 if(!['core_assets','content_library'].includes(table))throw Error('invalid subject');
 const piece=(await t.query(`SELECT *, ${table==='content_library'?'content_hash(content_library)':'NULL'} AS current_content_hash FROM ${table} WHERE id=$1`,[id])).rows[0];
 if(!piece||(!readOnly&&!['draft','in_review','needs_changes'].includes(piece.status)))throw Error('Guardian only updates reviewable revisions');
 piece.fact_ids=(await t.query(`SELECT approved_fact_id FROM content_fact_refs WHERE ${table==='core_assets'?'core_asset_id':'content_id'}=$1`,[id])).rows.map(r=>r.approved_fact_id);
 let media_qa=null;
 if(piece.format==='carousel') {
 const assets=(await t.query('SELECT * FROM media_assets WHERE content_id=$1 AND content_revision=$2',[id,piece.revision])).rows;
 const {digestFile}=await import('./package_check.mjs');
 if(assets.length&&assets.every(a=>a.qa_status==='pass'&&a.qa_report?.content_hash===piece.current_content_hash&&digestFile(a.storage_uri)===a.sha256))media_qa='pass';
 }
 if(readOnly){piece.status='draft';piece.approved_by=null;piece.approved_at=null;}
 const report=bridge('guardian',{piece,ctx:await context(t),facts:(await t.query('SELECT * FROM approved_facts')).rows,media_qa});
 if(readOnly)return report;
 await t.query(`UPDATE ${table} SET guardian_report=$2,brand_score=$3,icp_relevance_score=$4,
 guardian_checked_at=now(),guardian_threshold_profile='v0',status=$5 WHERE id=$1`,
 [id,JSON.stringify(report),report.brand_score,report.icp_relevance_score,report.verdict==='pass'?'in_review':'needs_changes']);
 for(const f of report.findings.filter(f=>['blocker','major'].includes(f.severity)))
 await t.query(`INSERT INTO correction_log(${table==='core_assets'?'core_asset_id':'content_id'},correction_type,severity,reason,corrected_by,corrector_name,memory_kind)
 VALUES($1,$2,$3,$4,'agent','Guardian','content_error')`,[id,f.type,f.severity,f.message]);
 return report;
}
