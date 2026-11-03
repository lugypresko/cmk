import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {openDB,tx,root} from '../db.mjs';
import {bridge,createCore,repurpose} from '../agents.mjs';
import {enqueue,run,tick,resumeHuman} from '../orchestrator.mjs';
let db,core,he,text;
const human={type:'human',name:'TEST HUMAN',run:'isolated-tests'};
before(async()=>{
 db=await openDB('memory://');
 for(const f of ['schema.sql',...fs.readdirSync(root+'migrations').filter(f=>/^\d+.*sql$/.test(f)).sort().map(f=>'migrations/'+f)])await db.exec(fs.readFileSync(root+f,'utf8'));
 he=bridge('load_piece',{path:'runs/001-human-gates/linkedin_text_he.md',variant:'B'});
 delete he.approved_by;delete he.approved_at;he.status='draft';
 core=await tx(db,t=>createCore(t,{}, {fixture:{title:'Synthetic test Core',primary_language:'he',body_he:he.body,cta_he:he.cta}}));
});
after(async()=>{await db.close();});
test('Core stops for human and cannot self-approve',async()=>{
 const w=await enqueue(db,'core',{research:{title:'Test idea',insight_he:'תובנה',confidentiality:'public'},core:{title:'Test',primary_language:'he',body_he:he.body}});
 const r=await run(db,w.id);assert.equal(r.state,'awaiting_human');assert.equal(r.blocked_on,'human_gate:approve_insight');
 await assert.rejects(resumeHuman(db,w.id,{type:'agent',name:'agent',run:'test'}));
 await assert.rejects(resumeHuman(db,w.id,human));
 assert.ok((await db.query('SELECT * FROM cmk.work_events WHERE work_item_id=$1',[w.id])).rows.length>=3);
});
test('Repurposer refuses unapproved Core',async()=>{
 await assert.rejects(tx(db,t=>repurpose(t,{core_id:core.id,format:'text_post',language:'he'},{fixture:he})),/approve_core/);
});
test('independent derivatives stop at gates; no publish',async()=>{
 // Synthetic approvals in memory only, never real business data.
 await tx(db,t=>t.query("UPDATE core_assets SET status='approved',approved_by='TEST HUMAN',approved_at=now(),brand_score=80,icp_relevance_score=80 WHERE id=$1",[core.id]),human);
 text=await enqueue(db,'derivative',{core_id:core.id,format:'text_post',language:'he',piece:he});
 const carousel=await enqueue(db,'derivative',{core_id:core.id,format:'carousel',language:'he',piece:{body:'כיתוב',slides:[{n:1,headline:'בדיקה'}]}});
 const a=await run(db,text.id),b=await run(db,carousel.id);
 assert.equal(a.state,'awaiting_human');assert.equal(a.blocked_on,'human_gate:approve_piece');
 assert.equal(b.state,'needs_changes');assert.equal(a.context.guardian.editorial.scorer,'heuristic-stub-v0');
 assert.equal((await db.query('SELECT count(*)::int AS n FROM cmk.publish_instances')).rows[0].n,0);
});
test('active lease excludes second worker and expired lease resumes',async()=>{
 const w=await enqueue(db,'derivative',{core_id:core.id,format:'text_post',language:'en',piece:{body:'Synthetic test content?',cta:'Who owns the decision?'}});
 await tx(db,t=>t.query("UPDATE work_items SET state='running',lease_owner='first',lease_until=now()+interval '1 hour' WHERE id=$1",[w.id]));
 assert.deepEqual(await tick(db,w.id,'second'),{idle:true});
 await tx(db,t=>t.query("UPDATE work_items SET lease_until=now()-interval '1 second' WHERE id=$1",[w.id]));
 const r=await tick(db,w.id,'second');assert.equal(r.step,'spec_gate');
 assert.equal((await db.query('SELECT count(*)::int AS n FROM cmk.content_library WHERE id=(SELECT subject_id FROM cmk.work_items WHERE id=$1)',[w.id])).rows[0].n,1);
});
test('malformed agent contract rejected before insert',async()=>{
 await assert.rejects(tx(db,t=>createCore(t,{}, {fixture:{title:'Bad',primary_language:'xx',body_en:'x'}})));
});

import os from 'node:os';
import path from 'node:path';
import {buildPackage,importMeasurement,importPast} from '../production.mjs';
import {proposeSlots,confirmSlot} from '../scheduler.mjs';
import {beginManual,recordOutcome,confirmURL} from '../distributor.mjs';
import {proposeReplay} from '../error_watcher.mjs';
let packageDir,slot,instance;
after(()=>{if(packageDir)fs.rmSync(packageDir,{recursive:true,force:true});});
test('approval boundary keeps agents from approving facts, prompts or pieces',async()=>{
 await assert.rejects(tx(db,t=>t.query("UPDATE approved_facts SET status='approved',approved_by='FAKE',approved_at=now()")),/human/);
 await assert.rejects(tx(db,t=>t.query("UPDATE prompt_versions SET status='approved',approved_by='FAKE',approved_at=now(),is_active=true")),/human/);
 await assert.rejects(tx(db,t=>t.query("UPDATE content_library SET status='approved',approved_by='FAKE',approved_at=now() WHERE id=(SELECT subject_id FROM work_items WHERE id=$1)",[text.id])),/human/);
 await assert.rejects(tx(db,t=>t.query("INSERT INTO lead_threads(owner) VALUES('not Itay')")),/human/);
});
test('approved package schedules only after explicit human confirmation',async()=>{
 const w=(await db.query('SELECT * FROM cmk.work_items WHERE id=$1',[text.id])).rows[0];
 await tx(db,t=>t.query("UPDATE content_library SET status='approved',approved_by='TEST HUMAN',approved_at=now() WHERE id=$1",[w.subject_id]),human);
 packageDir=fs.mkdtempSync(path.join(os.tmpdir(),'cmk-tests-'));
 await buildPackage(db,w.subject_id,packageDir);
 const plan=await proposeSlots(db,{start_date:'2026-11-10',package_dir:packageDir});
 assert.equal(plan.plan.status,'draft');assert.equal(plan.filled.length,1);slot=plan.filled[0];
 await assert.rejects(confirmSlot(db,slot.id,null,packageDir));
 const r=await confirmSlot(db,slot.id,human,packageDir);assert.ok(r.scheduled_at);
 const p=(await db.query('SELECT * FROM cmk.content_library WHERE id=$1',[w.subject_id])).rows[0];assert.equal(p.status,'scheduled');
 const time=new Date(p.scheduled_at);assert.equal(time.getUTCHours(),6);assert.equal(time.getUTCMinutes(),30);
});
test('unknown attempts are blocked at API and DB, then human may record live URL',async()=>{
 const started=await beginManual(db,slot.content_id,'test-profile',slot.id);instance=started.instance_id;
 const r=await recordOutcome(db,started.attempt_id,'unknown');assert.equal(r.state,'unknown');
 await assert.rejects(beginManual(db,slot.content_id,'test-profile',slot.id),/unknown/);
 await assert.rejects(tx(db,t=>t.query('INSERT INTO publish_attempts(publish_instance_id,attempt_no) VALUES($1,2)',[instance])),/unknown/);
 await assert.rejects(confirmURL(db,instance,'https://www.linkedin.com/posts/test',null));
 await assert.rejects(confirmURL(db,instance,'https://evil.example/posts/test',human));
 const url='https://www.linkedin.com/posts/itayfoyerstein_stripe-share-7518941479315070977-7PEg';
 assert.equal((await confirmURL(db,instance,url,human)).state,'confirmed');
 assert.equal((await db.query('SELECT status FROM cmk.rotation_slots WHERE id=$1',[slot.id])).rows[0].status,'published');
});
test('measurement reimport is idempotent and leaves human metrics null',async()=>{
 const file=path.join(root,'analytics_stripe_minions_en.xlsx');
 await importMeasurement(db,slot.content_id,file,'72h','2026-11-03T12:00:00Z');
 await importMeasurement(db,slot.content_id,file,'72h','2026-11-03T13:00:00Z');
 let rows=(await db.query('SELECT * FROM cmk.performance_logs WHERE content_id=$1',[slot.content_id])).rows;
 assert.equal(rows.length,1);assert.equal(rows[0].comments,27);assert.equal(rows[0].icp_conversations,null);assert.equal(rows[0].time_saved_minutes,null);
 await assert.rejects(importMeasurement(db,slot.content_id,file,'72h','2026-11-03T12:00:00Z',{icp_conversations:1}));
 await importMeasurement(db,slot.content_id,file,'72h','2026-11-03T12:00:00Z',{icp_conversations:1},human);
 await importMeasurement(db,slot.content_id,file,'72h','2026-11-03T12:00:00Z');
 rows=(await db.query('SELECT * FROM cmk.performance_logs WHERE content_id=$1',[slot.content_id])).rows;
 assert.equal(rows[0].icp_conversations,1);assert.equal(rows[0].confirmed_by,'TEST HUMAN');
});
test('ErrorWatcher replay never promotes and retains preference_once',async()=>{
 const r=await proposeReplay(db,{kind:'preference_once',reason:'shorter for this one',proposal:'one-off edit'});
 assert.equal(r.memory_kind,'preference_once');assert.equal(r.promoted_to,null);assert.equal(r.replay_report.passed,false);
});
test('expired exhausted lease stops rather than duplicating a draft',async()=>{
 const w=await enqueue(db,'derivative',{core_id:core.id,format:'text_post',language:'he',piece:he});
 await tx(db,t=>t.query("UPDATE work_items SET state='running',max_attempts=1,lease_until=now()-interval '1 second' WHERE id=$1",[w.id]));
 await tick(db,w.id);
 const p=(await db.query('SELECT * FROM cmk.work_items WHERE id=$1',[w.id])).rows[0];assert.equal(p.state,'stopped');assert.ok(p.stop_reason);
});
test('Workflow A resumes through actual synthetic human gates, then B HE/EN formats independently',async()=>{
 const en=bridge('load_piece',{path:'runs/001-human-gates/linkedin_text_en.md',variant:'B'});
 const w=await enqueue(db,'core',{research:{title:'Synthetic research',insight_he:'דוגמה לבדיקות',confidentiality:'public'},
 core:{title:'Synthetic bilingual Core',primary_language:'he',body_he:he.body,body_en:en.body,cta_he:he.cta,cta_en:en.cta}});
 let a=await run(db,w.id);assert.equal(a.blocked_on,'human_gate:approve_insight');
 await tx(db,t=>t.query("UPDATE core_insights SET status='approved',approved_by='TEST HUMAN',approved_at=now() WHERE id=$1",[a.context.insight_id]),human);
 await resumeHuman(db,w.id,human);a=await run(db,w.id);assert.equal(a.blocked_on,'human_gate:approve_core');
 await tx(db,t=>t.query("UPDATE core_assets SET status='approved',approved_by='TEST HUMAN',approved_at=now() WHERE id=$1",[a.subject_id]),human);
 await resumeHuman(db,w.id,human);a=await run(db,w.id);assert.equal(a.state,'done');
 for(const language of ['he','en'])for(const format of ['text_post','carousel']) {
 const source=bridge('load_piece',{path:`runs/001-human-gates/${format==='text_post'?'linkedin_text':'carousel'}_${language}.md`,variant:'B'});
 delete source.approved_by;delete source.approved_at;source.status='draft';
 const d=await enqueue(db,'derivative',{core_id:a.subject_id,format,language,piece:source},null,w.id);
 const r=await run(db,d.id);
 assert.ok(['awaiting_human','needs_changes'].includes(r.state));
 if(format==='carousel')assert.ok(r.context.guardian.findings.some(f=>f.check_id==='R-01'));
 }
});
test('derivative workflow proceeds through package preview, slot confirm and manual record gates',async()=>{
 const w=await enqueue(db,'derivative',{core_id:core.id,format:'text_post',language:'he',piece:he,
 package_dir:packageDir,start_date:'2027-02-01'});
 let r=await run(db,w.id);assert.equal(r.blocked_on,'human_gate:approve_piece');
 await tx(db,t=>t.query("UPDATE content_library SET status='approved',approved_by='TEST HUMAN',approved_at=now() WHERE id=$1",[r.subject_id]),human);
 await resumeHuman(db,w.id,human);r=await run(db,w.id);assert.equal(r.blocked_on,'human_gate:package_preview');
 await resumeHuman(db,w.id,human);r=await run(db,w.id);assert.equal(r.blocked_on,'human_gate:confirm_slot');
 const s=(await db.query('SELECT * FROM cmk.rotation_slots WHERE rotation_plan_id=$1 AND content_id=$2',[r.context.schedule_plan_id,r.subject_id])).rows[0];assert.ok(s);
 await confirmSlot(db,s.id,human,packageDir);await resumeHuman(db,w.id,human);
 r=await run(db,w.id);assert.equal(r.blocked_on,'human_gate:manual_publish_record');
 const attempt=await beginManual(db,r.subject_id,'test-profile',s.id);
 await confirmURL(db,attempt.instance_id,'https://www.linkedin.com/posts/fixture-full-flow',human);
 await resumeHuman(db,w.id,human);assert.equal((await run(db,w.id)).state,'done');
});
test('baseline replay can inspect published content without changing it',async()=>{
 const before=(await db.query('SELECT * FROM cmk.content_library WHERE id=$1',[slot.content_id])).rows[0];
 const r=await proposeReplay(db,{kind:'policy_gap',reason:'fixture replay',proposal:'proposal only',fixtures:[{table:'content_library',id:slot.content_id}]});
 assert.equal(r.replay_report.results.length,1);
 const after=(await db.query('SELECT * FROM cmk.content_library WHERE id=$1',[slot.content_id])).rows[0];
 assert.deepEqual(after,before);
 await assert.rejects(tx(db,t=>t.query("UPDATE correction_log SET promoted_to='brand_voice',promoted_at=now() WHERE id=$1",[r.id])),/human/);
});
