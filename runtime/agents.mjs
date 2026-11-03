import {spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {root} from './db.mjs';
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
async function judgment(t,key,input,{provider,fixture}={}) {
 if(fixture) return structuredClone(fixture); // Fixture mode is explicit, never a production prompt substitute.
 const prompt=(await t.query("SELECT * FROM prompt_versions WHERE prompt_key=$1 AND is_active AND status='approved'",[key])).rows[0];
 if(!prompt||!provider)throw Error('human_gate:activate_prompt_or_supply_provider');
 return provider({prompt,input});
}
async function insertDraft(t,table,row,cols) {
 const selected=cols.filter(k=>row[k]!==undefined);
 const vals=selected.map(k=>['key_points','slides','payload','media_refs'].includes(k)&&row[k]!==null?JSON.stringify(row[k]):row[k]);
 await t.query(`INSERT INTO ${table}(${selected.join(',')}) VALUES(${selected.map((_,i)=>'$'+(i+1)).join(',')})`,vals);
 return row;
}
export async function research(t,input,options) {
 const r=await judgment(t,'research.v0',input,options);
 if(!r.title||!['public','anonymized'].includes(r.confidentiality)||!(r.insight_he||r.insight_en))throw Error('Research output invalid/private');
 if(r.status&&r.status!=='draft'||r.approved_by||r.approved_at)throw Error('Research cannot approve');
 const row={id:randomUUID(),title:r.title,insight_he:r.insight_he,insight_en:r.insight_en,
  confidentiality:r.confidentiality,origin:'other',status:'draft',created_by:'agent'};
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
 for(const fid of row.fact_ids||[])await t.query(`INSERT INTO content_fact_refs(${col},approved_fact_id) VALUES($1,$2)`,[row.id,fid]);
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
export async function guardian(t,table,id) {
 if(!['core_assets','content_library'].includes(table))throw Error('invalid subject');
 const piece=(await t.query(`SELECT *, ${table==='content_library'?'content_hash(content_library)':'NULL'} AS current_content_hash FROM ${table} WHERE id=$1`,[id])).rows[0];
 if(!piece||!['draft','in_review','needs_changes'].includes(piece.status))throw Error('Guardian only updates reviewable revisions');
 piece.fact_ids=(await t.query(`SELECT approved_fact_id FROM content_fact_refs WHERE ${table==='core_assets'?'core_asset_id':'content_id'}=$1`,[id])).rows.map(r=>r.approved_fact_id);
 let media_qa=null;
 if(piece.format==='carousel') {
 const assets=(await t.query('SELECT * FROM media_assets WHERE content_id=$1 AND content_revision=$2',[id,piece.revision])).rows;
 const {digestFile}=await import('./package_check.mjs');
 if(assets.length&&assets.every(a=>a.qa_status==='pass'&&a.qa_report?.content_hash===piece.current_content_hash&&digestFile(a.storage_uri)===a.sha256))media_qa='pass';
 }
 const report=bridge('guardian',{piece,ctx:await context(t),facts:(await t.query('SELECT * FROM approved_facts')).rows,media_qa});
 await t.query(`UPDATE ${table} SET guardian_report=$2,brand_score=$3,icp_relevance_score=$4,
 guardian_checked_at=now(),guardian_threshold_profile='v0',status=$5 WHERE id=$1`,
 [id,JSON.stringify(report),report.brand_score,report.icp_relevance_score,report.verdict==='pass'?'in_review':'needs_changes']);
 for(const f of report.findings.filter(f=>['blocker','major'].includes(f.severity)))
 await t.query(`INSERT INTO correction_log(${table==='core_assets'?'core_asset_id':'content_id'},correction_type,severity,reason,corrected_by,corrector_name,memory_kind)
 VALUES($1,$2,$3,$4,'agent','Guardian','content_error')`,[id,f.type,f.severity,f.message]);
 return report;
}
