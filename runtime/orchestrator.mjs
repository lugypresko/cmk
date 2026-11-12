import {tx,root} from './db.mjs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {runResearchAgents} from '../research/coordinator.mjs';
import {complete,config,hash} from '../llm/client.mjs';
import {research,createCore,repurpose,guardian,prepareJudgment,promptKeys} from './agents.mjs';
import {qa,buildPackage} from './production.mjs';
export async function enqueue(db,kind,context,subject=null,parent=null) {
 if(!['core','derivative'].includes(kind))throw Error('kind must be core or derivative');
 return tx(db,async t=>{
 let runId='generation:'+randomUUID();
 if(kind==='derivative'&&context.core_id) {
 const parentWork=(await t.query("SELECT id,run_id FROM work_items WHERE kind='core' AND subject_id=$1 ORDER BY created_at DESC LIMIT 1",[context.core_id])).rows[0];
 if(parentWork){runId=parentWork.run_id;parent=parent||parentWork.id;}
 }
 return (await t.query(`INSERT INTO work_items(kind,step,owner,context,subject_table,subject_id,parent_work_item_id,run_id)
 VALUES($1,$2,'Orchestrator',$3,$4,$5,$6,$7) RETURNING *`,
 [kind,kind==='core'?'research':'repurpose',JSON.stringify(context),subject?'content_library':null,subject,parent,runId])).rows[0];
 });
}

export async function tick(db,id,runner='local-runner',options={}) {
 const w=await tx(db,async t=>{
 const w=(await t.query('SELECT * FROM work_items WHERE id=$1 FOR UPDATE',[id])).rows[0];
 if(!w||['done','stopped','failed','awaiting_human','needs_changes'].includes(w.state))return null;
 if(w.state==='running') {
 if(w.lease_until&&new Date(w.lease_until)>new Date())return null;
 await t.query("UPDATE work_items SET state='pending',lease_owner=null,lease_until=null WHERE id=$1",[id]);
 }
 if(w.attempt_count>=w.max_attempts){await t.query("UPDATE work_items SET state='stopped',stop_reason='max attempts exhausted' WHERE id=$1",[id]);return null;}
 return (await t.query("UPDATE work_items SET state='running',lease_owner=$2,lease_until=now()+interval '5 minutes' WHERE id=$1 RETURNING *",[id,runner])).rows[0];
 });
 if(!w)return {idle:true};
 try {
 let generated=null,prepared=null;
 const fixtureField={research:'research',create_core:'core',repurpose:'piece'}[w.step];
 if(fixtureField&&!w.context[fixtureField]) {
  // Reserve costs and make external calls outside the content transaction. A rollback cannot erase spend.
  const input=w.step==='create_core'?{insight_id:w.context.insight_id,language:w.context.language,goal:w.context.goal}:w.context;
  prepared=await tx(db,t=>prepareJudgment(t,promptKeys[w.step],input));
  const cfg=config(options.env||process.env,options.allowPaid===true);
  generated=w.step==='research'&&prepared.prompt.params.requires_collected_evidence?
   await runResearchAgents(db,prepared,{work:w,cfg,fetchImpl:options.fetchImpl}):
   await complete(db,prepared,{runId:w.run_id,callKey:w.id+':'+w.step,cfg,fetchImpl:options.fetchImpl});
 }
 const generatedProvider=prepared?async request=>{
  if(hash(request)!==hash(prepared))throw Error('llm_context_changed:review_before_retry');
  return generated;
 }:undefined;
 // Each complete step commits its outputs and next step atomically, so resume cannot duplicate drafts.
 return await tx(db,async t=>{
 const live=(await t.query('SELECT * FROM work_items WHERE id=$1 FOR UPDATE',[id])).rows[0];
 if(live.lease_owner!==runner||live.state!=='running')throw Error('lease lost');
 let step=w.step,ctx=w.context,table=w.subject_table,subject=w.subject_id,state='pending',blocked=null;
 if(step==='research') {
 const r=await research(t,ctx,{fixture:ctx.research,provider:generatedProvider});ctx={...ctx,insight_id:r.id};
 state='awaiting_human';blocked='human_gate:approve_insight';step='create_core';
 }else if(step==='create_core') {
 const r=await createCore(t,{insight_id:ctx.insight_id,language:ctx.language,goal:ctx.goal},{fixture:ctx.core,provider:generatedProvider});table='core_assets';subject=r.id;step='spec_gate';
 }else if(step==='repurpose') {
 const r=await repurpose(t,ctx,{fixture:ctx.piece,provider:generatedProvider});table='content_library';subject=r.id;step='spec_gate';
 }else if(step==='spec_gate') {
 const report=await guardian(t,table,subject);ctx={...ctx,guardian:report};step='fact_gate';
 }else if(step==='fact_gate') {
 step='editorial_review';
 }else if(step==='editorial_review') {
 const report=ctx.guardian;
 if(report.verdict==='pass'){state='awaiting_human';blocked=table==='core_assets'?'human_gate:approve_core':'human_gate:approve_piece';step='human_approval';}
 else if(table==='content_library'&&report.findings.some(f=>f.check_id==='R-01')&&ctx.render_file){step='render_qa';}
 else {state='needs_changes';blocked='guardian:'+report.verdict;}
 }else if(step==='human_approval') {
 const r=(await t.query(`SELECT status FROM ${table} WHERE id=$1`,[subject])).rows[0];
 if(r?.status!=='approved')throw Error('human_gate:approval_required');
 if(table==='core_assets'){state='done';}else step='package';
 }else if(step==='package') {
 // Files are idempotent; avoid nested DB transactions.
 state='awaiting_human';blocked='human_gate:package_preview';step='schedule';
 }else if(step==='schedule') {
 const {proposeSlots}=await import('./scheduler.mjs');
 if(!ctx.start_date)throw Error('schedule start_date required in work context');
 const proposal=await proposeSlots(t,{start_date:ctx.start_date,package_dir:ctx.package_dir},true);
 ctx={...ctx,schedule_plan_id:proposal.plan.id};
 state='awaiting_human';blocked='human_gate:confirm_slot';step='publish';
 }else if(step==='publish') {
 state='awaiting_human';blocked='human_gate:manual_publish_record';step='verify_publish';
 }else if(step==='verify_publish') {
 const p=(await t.query("SELECT 1 FROM publish_instances WHERE content_id=$1 AND state='confirmed'",[subject])).rows;
 if(!p.length)throw Error('human_gate:manual_publish_record');state='done';
 }else if(step==='render_qa') {
 // External file inspection happens outside this DB transaction, below.
 step='spec_gate';
 }else throw Error('unsupported step');
 if(prepared&&['core_assets','content_library'].includes(table))await t.query(`UPDATE ${table} SET prompt_version_id=$2 WHERE id=$1`,[subject,prepared.prompt.id]);
 await t.query(`UPDATE work_items SET state=$2,step=$3,subject_table=$4,subject_id=$5,context=$6,
 blocked_on=$7,owner=$8,lease_owner=null,lease_until=null,attempt_count=0 WHERE id=$1`,
 [id,state,step,table,subject,JSON.stringify(ctx),blocked,state==='awaiting_human'?'Itay':'Orchestrator']);
 return {id,state,step,blocked_on:blocked};
 });
 }catch(e) {
 await tx(db,t=>t.query("UPDATE work_items SET state='needs_changes',last_error=$2,blocked_on=$3,lease_owner=null,lease_until=null WHERE id=$1 AND state='running' AND lease_owner=$4",[id,String(e.message),e.message.startsWith('human_gate:')?e.message:'runtime_error',runner]));
 return {id,state:'needs_changes',error:e.message};
 }
}
export async function run(db,id,runner,options={}) {
 for(let n=0;n<32;n++) {
 const w=(await db.query('SELECT * FROM cmk.work_items WHERE id=$1',[id])).rows[0];
 if(!w||['awaiting_human','needs_changes','done','failed','stopped'].includes(w.state))return w;
 if(w.state==='running'&&w.lease_until&&new Date(w.lease_until)>new Date())return {idle:true};
 if(w.step==='render_qa') {
 const r=await qa(db,w.subject_id,w.context.render_file,w.context.alt_text||[]);
 if(r.status!=='pass'){
 await tx(db,t=>t.query("UPDATE work_items SET state='running' WHERE id=$1 AND state='pending'",[id]));
 await tx(db,t=>t.query("UPDATE work_items SET state='needs_changes',blocked_on='render_qa_failed' WHERE id=$1",[id]));return {state:'needs_changes'};
 }
 }
 if(w.step==='package') {
 const dir=w.context.package_dir||path.join(root,'packages');
 const manifest=await buildPackage(db,w.subject_id,dir);
 await tx(db,t=>t.query("UPDATE work_items SET context=context||$2::jsonb WHERE id=$1",[id,JSON.stringify({package_dir:dir,package_path:path.join(dir,manifest.content_id,'r'+manifest.revision,'package.json')})]));
 }

 const r=await tick(db,id,runner,options);if(r.idle)return r;
 }throw Error('step budget exhausted');
}
export async function resumeHuman(db,id,actor) {
 if(actor?.type!=='human'||!actor.name?.trim())throw Error('Explicit human actor required');
 return tx(db,async t=>{
 const w=(await t.query('SELECT * FROM work_items WHERE id=$1 FOR UPDATE',[id])).rows[0];
 if(w.state!=='awaiting_human')throw Error('Not at human gate');
 // Acknowledgement is not approval: validate the actual authoritative row.
 if(w.blocked_on==='human_gate:approve_insight') {
 const r=(await t.query('SELECT status FROM core_insights WHERE id=$1',[w.context.insight_id])).rows[0];
 if(r?.status!=='approved')throw Error('Insight remains unapproved');
 }else if(['human_gate:approve_core','human_gate:approve_piece'].includes(w.blocked_on)) {
 const r=(await t.query(`SELECT status FROM ${w.subject_table} WHERE id=$1`,[w.subject_id])).rows[0];
 if(r?.status!=='approved')throw Error('Subject remains unapproved');
 }else if(w.blocked_on==='human_gate:confirm_slot') {
 if(!(await t.query("SELECT 1 FROM rotation_slots WHERE content_id=$1 AND status='confirmed'",[w.subject_id])).rows.length)throw Error('Slot remains unconfirmed');
 }else if(w.blocked_on==='human_gate:manual_publish_record') {
 if(!(await t.query("SELECT 1 FROM publish_instances WHERE content_id=$1 AND state='confirmed'",[w.subject_id])).rows.length)throw Error('Publish remains unconfirmed');
 }
 await t.query("UPDATE work_items SET state='pending',blocked_on=null,attempt_count=0 WHERE id=$1",[id]);
 },actor);
}

export async function preview(db,id) {
 const w=(await db.query('SELECT * FROM cmk.work_items WHERE id=$1',[id])).rows[0];
 if(!w)throw Error('work item not found');
 const input=w.step==='create_core'?{insight_id:w.context.insight_id,language:w.context.language,goal:w.context.goal}:w.context;
 const key=promptKeys[w.step];
 if(!key)return {mode:'dry-run',id,state:w.state,step:w.step,next:'No model call at this step',external_calls:0};
 try {
 const r=await tx(db,t=>prepareJudgment(t,key,input));
 return {mode:'dry-run',id,state:w.state,step:w.step,prompt_key:key,prompt_version:r.prompt.version,
 context_bytes:Buffer.byteLength(JSON.stringify(r),'utf8'),usable_fact_ids:r.memory.approved_facts.map(f=>f.id),external_calls:0};
 }catch(e){return {mode:'dry-run',id,state:w.state,step:w.step,blocked_on:e.message,external_calls:0};}
}
export async function retryHuman(db,id,actor) {
 if(actor?.type!=='human'||!actor.name?.trim())throw Error('Explicit human actor required');
 return tx(db,async t=>{
 const w=(await t.query('SELECT * FROM work_items WHERE id=$1 FOR UPDATE',[id])).rows[0];
 if(!w||w.state!=='needs_changes'||!promptKeys[w.step])throw Error('Only a blocked generation step can be retried');
 // Traverse allowed transitions without consuming an attempt until the next worker claims it.
 if(w.attempt_count>=w.max_attempts)throw Error('Generation attempts exhausted; explicit new work item required');
 await t.query("UPDATE work_items SET state='running' WHERE id=$1",[id]);
 await t.query("UPDATE work_items SET state='pending',attempt_count=$2,last_error=null,blocked_on=null,lease_owner=null,lease_until=null WHERE id=$1",[id,w.attempt_count]);
 // The durable call ledger separately prevents resending failed/unknown calls.
 },actor);
}
