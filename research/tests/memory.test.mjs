import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {openDB,root,tx} from '../../runtime/db.mjs';
let db;
const human={type:'human',name:'TEST HUMAN',run:'isolated-research-tests'};
before(async()=>{
 db=await openDB('memory://');
 for(const f of ['schema.sql',...fs.readdirSync(root+'migrations').filter(f=>/^\d{3}_.*\.sql$/.test(f)).sort().map(f=>'migrations/'+f)])await db.exec(fs.readFileSync(root+f,'utf8'));
});
after(async()=>{if(db)await db.close();});

test('focused research version is a draft proposal and preserves existing prompt history',async()=>{
 const rows=(await db.query("SELECT * FROM cmk.prompt_versions WHERE prompt_key='research.v0' ORDER BY version")).rows;
 assert.equal(rows.length,2);assert.deepEqual(rows.map(r=>r.version),[1,2]);
 for(const r of rows){assert.equal(r.status,'draft');assert.equal(r.is_active,false);assert.equal(r.approved_by,null);assert.equal(r.approved_at,null);}
 assert.equal(rows[1].parent_id,rows[0].id);
 assert.equal(rows[1].params.requires_collected_evidence,true);
 assert.equal(rows[1].params.research_profile_key,'the_push.social_research');
 assert.equal(rows[1].params.research_profile_version,1);
 assert.match(rows[1].body,/hook/i);assert.match(rows[1].body,/source/i);assert.match(rows[1].body,/draft/i);
 assert.match(rows[0].body,/From the supplied idea or source notes/);
});

test('The Push profile is focused on the agreed management and AI-code-factory clusters',async()=>{
 const p=(await db.query("SELECT * FROM cmk.research_profiles WHERE profile_key='the_push.social_research' AND version=1")).rows[0];
 assert.ok(p);assert.equal(p.status,'draft');assert.equal(p.is_active,false);assert.equal(p.approved_by,null);
 assert.deepEqual(p.body.clusters.map(c=>c.id).sort(),['ai_code_factory','ai_management','leadership_delegation','manager_bottleneck','ownership_execution'].sort());
 for(const c of p.body.clusters){assert.ok((c.terms_he||c.keywords_he).length>0);assert.ok((c.terms_en||c.keywords_en).length>0);}
 const raw=JSON.stringify(p.body);
 assert.match(raw,/bottleneck/i);assert.match(raw,/code factory/i);assert.match(raw,/צוואר/);
});

test('agents cannot activate research profile or prompt and human approval does not activate unrelated memory',async()=>{
 const p=(await db.query("SELECT id FROM cmk.research_profiles WHERE profile_key='the_push.social_research' AND version=1")).rows[0];
 await assert.rejects(tx(db,t=>t.query("UPDATE research_profiles SET status='approved',approved_by='FAKE',approved_at=now(),is_active=true WHERE id=$1",[p.id])),/human/i);
 await assert.rejects(tx(db,t=>t.query("UPDATE prompt_versions SET is_active=true WHERE prompt_key='research.v0' AND version=2")),/human/i);
 await assert.rejects(tx(db,t=>t.query('UPDATE research_profiles SET is_active=true WHERE id=$1',[p.id]),human),/check constraint/i);
 assert.equal((await db.query("SELECT count(*)::int AS n FROM cmk.prompt_versions WHERE is_active")).rows[0].n,0);
 assert.equal((await db.query("SELECT count(*)::int AS n FROM cmk.approved_facts WHERE status='approved'")).rows[0].n,0);
});

test('research profile content is immutable even for a human; edits require a new version',async()=>{
 const p=(await db.query("SELECT id FROM cmk.research_profiles WHERE profile_key='the_push.social_research' AND version=1")).rows[0];
 await assert.rejects(tx(db,t=>t.query("UPDATE research_profiles SET body=body||'{\"scope\":\"generic AI news\"}'::jsonb WHERE id=$1",[p.id]),human),/immutable|new version/i);
});

test('topic and hook researchers are separate inactive draft prompts, not implicit publication approvals',async()=>{
 const rows=(await db.query("SELECT * FROM cmk.prompt_versions WHERE prompt_key IN ('research.topics.v0','research.hooks.v0') ORDER BY prompt_key")).rows;
 assert.equal(rows.length,2);
 assert.deepEqual(rows.map(r=>r.prompt_key),['research.hooks.v0','research.topics.v0']);
 for(const r of rows){assert.equal(r.status,'draft');assert.equal(r.is_active,false);assert.equal(r.approved_by,null);assert.equal(r.approved_at,null);assert.match(r.body,/source/i);}
 assert.equal((await db.query("SELECT count(*)::int AS n FROM cmk.content_library WHERE status IN ('approved','scheduled','published')")).rows[0].n,0);
});
