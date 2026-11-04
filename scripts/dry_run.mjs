// Demonstrates Workflow A stopping at its first human gate. No approvals, no LLM, no sends.
import {openDB,root} from '../runtime/db.mjs';
import {bridge} from '../runtime/agents.mjs';
import {enqueue,run} from '../runtime/orchestrator.mjs';
const db=await openDB();
try {
 const he=bridge('load_piece',{path:'runs/001-human-gates/linkedin_text_he.md',variant:'B'});
 const w=await enqueue(db,'core',{fixture_mode:true,research:{title:'Fixture idea for dry-run',insight_he:'בדיקת זרימת העבודה בלבד',confidentiality:'public'},
 core:{title:'Fixture Core',primary_language:'he',body_he:he.body,cta_he:he.cta}});
 const result=await run(db,w.id);
 console.log(JSON.stringify({id:result.id,state:result.state,blocked_on:result.blocked_on,step:result.step},null,2));
}finally{await db.close();}
