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
test('manual handoff requires a confirmed slot and intact current package before any attempt',async()=>{
 const p=(await db.query('SELECT * FROM cmk.content_library WHERE id=$1',[slot.content_id])).rows[0];
 const counts=async()=>(await db.query('SELECT (SELECT count(*)::int FROM cmk.publish_instances) AS instances,(SELECT count(*)::int FROM cmk.publish_attempts) AS attempts')).rows[0];
 const before=await counts();
 await assert.rejects(beginManual(db,p.id,'test-profile'),/Human-confirmed slot required/);
 const unconfirmed=(await db.query("SELECT id FROM cmk.rotation_slots WHERE status<>'confirmed' LIMIT 1")).rows[0];
 assert.ok(unconfirmed);
 await assert.rejects(beginManual(db,p.id,'test-profile',unconfirmed.id,packageDir),/Slot must be human-confirmed/);
 const dest=path.join(packageDir,p.id,'r'+p.revision),manifestFile=path.join(dest,'package.json');
 const manifest=fs.readFileSync(manifestFile,'utf8'),m=JSON.parse(manifest);
 fs.unlinkSync(manifestFile);
 await assert.rejects(beginManual(db,p.id,'test-profile',slot.id,packageDir),/Valid current package/);
 fs.writeFileSync(manifestFile,manifest);
 const asset=path.join(dest,Object.keys(m.files)[0]),original=fs.readFileSync(asset);
 fs.appendFileSync(asset,'tamper');
 await assert.rejects(beginManual(db,p.id,'test-profile',slot.id,packageDir),/Valid current package/);
 fs.writeFileSync(asset,original);
 fs.writeFileSync(manifestFile,JSON.stringify({...m,content_hash:'stale-hash'}));
 await assert.rejects(beginManual(db,p.id,'test-profile',slot.id,packageDir),/Valid current package/);
 fs.writeFileSync(manifestFile,manifest);
 assert.deepEqual(await counts(),before);
});
test('unknown attempts are blocked at API and DB, then human may record live URL',async()=>{
 const started=await beginManual(db,slot.content_id,'test-profile',slot.id,packageDir);instance=started.instance_id;
 const r=await recordOutcome(db,started.attempt_id,'unknown');assert.equal(r.state,'unknown');
 await assert.rejects(beginManual(db,slot.content_id,'test-profile',slot.id,packageDir),/unknown/);
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
 const attempt=await beginManual(db,r.subject_id,'test-profile',s.id,packageDir);
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
test('exact repeat reuses the approved revision and blocks when the hash or facts change',async()=>{
 const id=slot.content_id;
 const revision=(await db.query('SELECT revision FROM cmk.content_library WHERE id=$1',[id])).rows[0].revision;
 const hash=(await db.query('SELECT content_hash(c) AS h FROM cmk.content_library c WHERE id=$1',[id])).rows[0].h;
 const openPlan=(await db.query(`SELECT p.status FROM cmk.rotation_slots s JOIN cmk.rotation_plans p ON p.id=s.rotation_plan_id WHERE s.id=$1`,[slot.id])).rows[0];
 assert.equal(openPlan.status,'draft');
 const before=await proposeSlots(db,{start_date:'2026-11-24',name:'before exact rule',package_dir:packageDir});
 assert.ok(!before.filled.some(s=>String(s.content_id)===String(id)));
 await assert.rejects(tx(db,t=>t.query(`UPDATE content_library SET is_exact_repeatable=true,repeat_every_days=14,repeat_until='2027-06-01',max_repeats=3,repeat_approved_content_hash=$2,repeat_asset_hashes='[]'::jsonb WHERE id=$1`,[id,hash])),/exact repeat rule is human-only/);
 await tx(db,t=>t.query(`UPDATE content_library SET is_exact_repeatable=true,repeat_every_days=14,repeat_until='2027-06-01',max_repeats=3,
  repeat_approved_content_hash=$2,repeat_asset_hashes='[]'::jsonb,last_published_at='2026-11-10T06:30:00+02' WHERE id=$1`,[id,hash]),human);
 const coreId=(await db.query('SELECT core_asset_id FROM cmk.content_library WHERE id=$1',[id])).rows[0].core_asset_id;
 const spec=(await db.query(`SELECT id FROM cmk.format_specs WHERE format='text_post' AND channel='linkedin' AND language='en' AND is_active LIMIT 1`)).rows[0];
 await tx(db,async t=>{
  const rev=(await t.query(`SELECT coalesce(max(revision),0)+1 AS n FROM content_library WHERE core_asset_id=$1 AND format='text_post' AND channel='linkedin' AND language='en'`,[coreId])).rows[0].n;
  const sibling=(await t.query(`INSERT INTO content_library(core_asset_id,format_spec_id,format,channel,language,revision,body,status,brand_score,icp_relevance_score,approved_by,approved_at)
   VALUES($1,$2,'text_post','linkedin','en',$3,'sibling core piece','approved',80,80,'TEST HUMAN',now()) RETURNING id`,[coreId,spec.id,rev])).rows[0];
  const plan=(await t.query(`INSERT INTO rotation_plans(name,start_date,daily_caps,constraints,status) VALUES('sibling-core','2026-11-22','{"linkedin":1}','{}','draft') RETURNING id`)).rows[0];
  await t.query(`INSERT INTO rotation_slots(rotation_plan_id,day,channel,format,language,local_time,content_id,status,confirmed_by,confirmed_at,rationale)
   VALUES($1,1,'linkedin','text_post','en','08:30',$2,'confirmed','TEST HUMAN',now(),'same core inside the 4-day gap')`,[plan.id,sibling.id]);
 },human);
 assert.ok(Math.abs((Date.parse('2026-11-24')-Date.parse('2026-11-22'))/86400000)<4);
 const next=await proposeSlots(db,{start_date:'2026-11-24',name:'exact-repeat',package_dir:packageDir});
 const placed=next.filled.find(s=>String(s.content_id)===String(id));
 assert.ok(placed);
 assert.match(placed.rationale,/Exact repeat/);
 assert.equal((await db.query('SELECT revision,status FROM cmk.content_library WHERE id=$1',[id])).rows[0].revision,revision);
 assert.equal((await db.query('SELECT status FROM cmk.content_library WHERE id=$1',[id])).rows[0].status,'published');
 await confirmSlot(db,placed.id,human,packageDir);
 const first=(await db.query('SELECT sent_content_hash FROM cmk.publish_instances WHERE content_id=$1 ORDER BY created_at',[id])).rows[0];
 const started=await beginManual(db,id,'test-profile',placed.id,packageDir);
 const inst=(await db.query('SELECT content_revision,sent_content_hash FROM cmk.publish_instances WHERE id=$1',[started.instance_id])).rows[0];
 assert.equal(inst.content_revision,revision);
 assert.equal(inst.sent_content_hash,hash);
 assert.equal(inst.sent_content_hash,first.sent_content_hash);
 await confirmURL(db,started.instance_id,'https://www.linkedin.com/posts/exact-repeat-cycle',human);
 assert.equal((await db.query('SELECT repeats_done,status FROM cmk.content_library WHERE id=$1',[id])).rows[0].repeats_done,1);
 await tx(db,t=>t.query(`UPDATE content_library SET last_published_at='2026-11-24T06:30:00+02' WHERE id=$1`,[id]),human);
 await tx(db,t=>t.query(`UPDATE content_library SET repeat_asset_hashes=$2::jsonb WHERE id=$1`,[id,JSON.stringify(['a'.repeat(64)])]),human);
 const assets=await proposeSlots(db,{start_date:'2026-12-08',name:'asset-block',package_dir:packageDir});
 assert.ok(assets.blocked_exact_repeats.some(b=>String(b.content_id)===String(id)&&b.reason==='asset_hash_mismatch'));
 assert.ok(!assets.filled.some(s=>String(s.content_id)===String(id)));
 await tx(db,t=>t.query(`UPDATE content_library SET repeat_asset_hashes='[]'::jsonb WHERE id=$1`,[id]),human);
 const fact=(await tx(db,t=>t.query(`INSERT INTO approved_facts(fact_key,category,statement_en,source_url,status,approved_by,approved_at,valid_until)
  VALUES('proof.exact_repeat_test','proof','Synthetic exact-repeat fact','https://example.invalid/exact-repeat','approved','TEST HUMAN',now(),now()-interval '1 day') RETURNING id`),human)).rows[0];
 await tx(db,t=>t.query('INSERT INTO content_fact_refs(content_id,approved_fact_id) VALUES($1,$2)',[id,fact.id]));
 const expired=await proposeSlots(db,{start_date:'2026-12-08',name:'fact-expired',package_dir:packageDir});
 assert.ok(expired.blocked_exact_repeats.some(b=>String(b.content_id)===String(id)&&b.reason==='fact_not_usable'));
 assert.ok(!expired.filled.some(s=>String(s.content_id)===String(id)));
 await tx(db,t=>t.query(`UPDATE approved_facts SET status='retired',valid_until=NULL WHERE id=$1`,[fact.id]),human);
 const retired=await proposeSlots(db,{start_date:'2026-12-08',name:'fact-retired',package_dir:packageDir});
 assert.ok(retired.blocked_exact_repeats.some(b=>String(b.content_id)===String(id)&&b.reason==='fact_not_usable'));
 await tx(db,t=>t.query('DELETE FROM content_fact_refs WHERE content_id=$1 AND approved_fact_id=$2',[id,fact.id]));
 const other=(await db.query(`SELECT id FROM cmk.content_library WHERE id<>$1 AND status='published' AND channel='linkedin' AND format IN ('text_post','carousel') ORDER BY created_at LIMIT 1`,[id])).rows[0];
 assert.ok(other);
 await tx(db,t=>t.query(`UPDATE content_library SET is_evergreen=true,recycle_after_days=14,last_published_at='2026-01-01T08:00:00+02' WHERE id=$1`,[other.id]),human);
 await tx(db,t=>t.query(`UPDATE content_library SET body=body||' drift' WHERE id=$1`,[id]));
 const kept=(await db.query('SELECT status,approved_by,edited_after_approval,is_exact_repeatable FROM cmk.content_library WHERE id=$1',[id])).rows[0];
 assert.equal(kept.status,'published');
 assert.equal(kept.approved_by,'TEST HUMAN');
 assert.equal(kept.edited_after_approval,true);
 assert.equal(kept.is_exact_repeatable,true);
 const drifted=await proposeSlots(db,{start_date:'2026-12-08',name:'hash-block',package_dir:packageDir});
 assert.ok(drifted.blocked_exact_repeats.some(b=>String(b.content_id)===String(id)&&b.reason==='hash_mismatch'));
 assert.ok(!drifted.filled.some(s=>String(s.content_id)===String(id)));
 assert.ok(drifted.new_revision_candidates.map(String).includes(String(other.id)));
 assert.ok(!drifted.filled.some(s=>String(s.content_id)===String(other.id)));
 const probe=await tx(db,async t=>{
  const plan=(await t.query(`INSERT INTO rotation_plans(name,start_date,daily_caps,constraints,status) VALUES('drift-probe','2026-12-08','{"linkedin":1}','{}','draft') RETURNING id`)).rows[0];
  return (await t.query(`INSERT INTO rotation_slots(rotation_plan_id,day,channel,format,language,local_time,content_id,status,rationale)
   VALUES($1,1,'linkedin','text_post','he','08:30',$2,'filled','probe') RETURNING id`,[plan.id,id])).rows[0].id;
 });
 await assert.rejects(confirmSlot(db,probe,human,packageDir),/Exact repeat blocked: hash_mismatch/);
});

test('013 negative tests detect removed authorization or draft CHECK protections',async()=>{
 const sql=fs.readFileSync(root+'migrations/test_013.sql','utf8');
 // Baseline test has no lasting writes.
 await db.exec('BEGIN');
 try {await db.exec(sql);} finally {await db.exec('ROLLBACK');}
 await assert.rejects(db.transaction(async t=>{
  await t.exec('ALTER TABLE cmk.prompt_versions DISABLE TRIGGER prompt_versions_human_boundary');
  await t.exec(sql);
 }),/check constraint/);
 await assert.rejects(db.transaction(async t=>{
  const rows=(await t.query("SELECT conname FROM pg_constraint WHERE conrelid='cmk.prompt_versions'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%is_active%'")).rows;
  assert.equal(rows.length,1);
  await t.exec('ALTER TABLE cmk.prompt_versions DROP CONSTRAINT "'+rows[0].conname.replaceAll('"','""')+'"');
  await t.exec(sql);
 }),/human activation of a draft was not blocked by CHECK/);
});
