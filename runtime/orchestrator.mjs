import {tx} from './db.mjs';
import {research,createCore,repurpose,guardian} from './agents.mjs';
import {qa,buildPackage} from './production.mjs';
export async function enqueue(db,kind,context,subject=null,parent=null) {
 if(!['core','derivative'].includes(kind))throw Error('kind must be core or derivative');
 return tx(db,async t=>(await t.query(`INSERT INTO work_items(kind,step,owner,context,subject_table,subject_id,parent_work_item_id,run_id)
 VALUES($1,$2,'Orchestrator',$3,$4,$5,$6,'phase-0-1') RETURNING *`,
 [kind,kind==='core'?'research':'repurpose',JSON.stringify(context),subject?'content_library':null,subject,parent])).rows[0]);
}
export async function tick(db,id,runner='local-runner') {
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
 // Each complete step commits its outputs and next step atomically, so resume cannot duplicate drafts.
 return await tx(db,async t=>{
 const live=(await t.query('SELECT * FROM work_items WHERE id=$1 FOR UPDATE',[id])).rows[0];
 if(live.lease_owner!==runner||live.state!=='running')throw Error('lease lost');
 let step=w.step,ctx=w.context,table=w.subject_table,subject=w.subject_id,state='pending',blocked=null;
 if(step==='research') {
 const r=await research(t,ctx,{fixture:ctx.research});ctx={...ctx,insight_id:r.id};
 state='awaiting_human';blocked='human_gate:approve_insight';step='create_core';
 }else if(step==='create_core') {
 const r=await createCore(t,{insight_id:ctx.insight_id},{fixture:ctx.core});table='core_assets';subject=r.id;step='spec_gate';
 }else if(step==='repurpose') {
 const r=await repurpose(t,ctx,{fixture:ctx.piece});table='content_library';subject=r.id;step='spec_gate';
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
export async function run(db,id,runner) {
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
 if(w.step==='package')await buildPackage(db,w.subject_id,w.context.package_dir);

 const r=await tick(db,id,runner);if(r.idle)return r;
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
