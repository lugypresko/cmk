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
