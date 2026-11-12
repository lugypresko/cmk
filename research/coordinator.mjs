// Bounded runtime agents, not coding assistants: each has its own approved prompt and durable output.
import {tx} from '../runtime/db.mjs';
import {complete,hash} from '../llm/client.mjs';
import {validateReport} from './runtime.mjs';
async function rolePrompt(t,key) {
 const p=(await t.query("SELECT id,prompt_key,version,body,params FROM prompt_versions WHERE prompt_key=$1 AND status='approved' AND is_active",[key])).rows[0];
 if(!p)throw Error('human_gate:activate_prompt:'+key);return p;
}
function draftOnly(r) {
 if(!r||typeof r!=='object'||Array.isArray(r)||r.approved_by||r.approved_at||(r.status&&r.status!=='draft'))throw Error('research_agent_must_propose_draft');
}
export async function runResearchAgents(db,base,{work,cfg,fetchImpl}={}) {
 const evidence=base.input.research.sources;
 // Check every role's approval before making the first paid call.
 const prompts=await tx(db,async t=>({topics:await rolePrompt(t,base.prompt.params.topic_prompt_key||'research.topics.v0'),
 hooks:await rolePrompt(t,base.prompt.params.hook_prompt_key||'research.hooks.v0'),synthesis:base.prompt}));
 const outputs={};
 for(const role of ['topics','hooks','synthesis']) {
 const output_contract=role==='synthesis'?base.output_contract:{required:[role==='topics'?'topics':'hook_examples','coverage_notes'],
 properties:role==='topics'?{topics:'array of {topic,managerial_pain,relevance,source_ids}',coverage_notes:'nonempty array of strings',status:'draft'}:
 {hook_examples:'array of {source_ids,observed_opening,mechanism}; observed_opening must equal the full first line of a captured full_post',recommended_angles:'array of {angle,original_hooks,source_ids}',coverage_notes:'nonempty array of strings',status:'draft'},
 note:'Do not output numeric metrics. Reference only supplied source_ids. Empty examples are correct when evidence is missing.'};
 const request={...base,prompt:prompts[role],output_contract,input:{...base.input,research_role:role,
 ...(role==='hooks'?{topic_agent:outputs.topics}:{}),...(role==='synthesis'?{topic_agent:outputs.topics,hook_agent:outputs.hooks}:{})}};
 const fingerprint=hash(request);
 const task=await tx(db,async t=>{
 const old=(await t.query('SELECT * FROM research_agent_tasks WHERE work_item_id=$1 AND role=$2 FOR UPDATE',[work.id,role])).rows[0];
 if(old&&old.input_hash!==fingerprint)throw Error('research_agent_context_changed:new_work_item_required');
 if(old?.state==='done')return old;
 if(old){await t.query("UPDATE research_agent_tasks SET state='running',error_code=null WHERE id=$1",[old.id]);return old;}
 return (await t.query(`INSERT INTO research_agent_tasks(work_item_id,research_run_id,role,prompt_version_id,input_hash,state)
 VALUES($1,$2,$3,$4,$5,'running') RETURNING *`,[work.id,base.input.research.research_run_id,role,prompts[role].id,fingerprint])).rows[0];
 });
 if(task.state==='done'){outputs[role]=task.output;continue;}
 try {
 const r=await complete(db,request,{runId:work.run_id,callKey:work.id+':research:'+role,cfg,fetchImpl});
 draftOnly(r);
 if(role==='topics')validateReport({topics:r.topics,hook_examples:[],recommended_angles:[],recommended_topic:null,coverage_notes:r.coverage_notes},evidence);
 else if(role==='hooks')validateReport({topics:[],hook_examples:r.hook_examples,recommended_angles:r.recommended_angles||[],recommended_topic:null,coverage_notes:r.coverage_notes},evidence);
 else validateReport(r.research_report,evidence,{synthesis:true});
 await tx(db,t=>t.query("UPDATE research_agent_tasks SET state='done',output=$2,completed_at=now() WHERE id=$1",[task.id,JSON.stringify(r)]));
 outputs[role]=r;
 }catch(e) {
 await tx(db,t=>t.query("UPDATE research_agent_tasks SET state='blocked',error_code=$2,completed_at=now() WHERE id=$1",[task.id,e.message.startsWith('human_gate:')?e.message:'research_agent_failed']));
 throw e;
 }
 }
 return outputs.synthesis;
}
