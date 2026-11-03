import {tx} from './db.mjs';
import {guardian} from './agents.mjs';
export const kinds=['content_error','preference_once','policy_gap','fact_change','hypothesis','infra_failure'];
export async function proposeReplay(db,{kind,reason,proposal,scope={},fixtures=[]}) {
 if(!kinds.includes(kind)||!reason?.trim()||!proposal?.trim())throw Error('classification/reason/proposal required');
 return tx(db,async t=>{
 const results=[];
 for(const f of fixtures){
 // Replay uses DB context but rolls back all Guardian content changes in a savepoint.
 await t.exec('SAVEPOINT replay');
 try{const r=await guardian(t,f.table,f.id);results.push({id:f.id,verdict:r.verdict,expected:f.expected??null,match:f.expected?r.verdict===f.expected:null});}
 finally{await t.exec('ROLLBACK TO SAVEPOINT replay');await t.exec('RELEASE SAVEPOINT replay');}
 }
 const replay={kind:'guardian-fixture-replay-stub-v0',candidate_applied:false,results,
 note:'Baseline Guardian only. Candidate rule execution is not implemented; promotion requires human review.',passed:false};
 return (await t.query(`INSERT INTO correction_log(correction_type,severity,reason,rule_candidate,corrected_by,corrector_name,memory_kind,rule_reason,rule_scope,replay_report)
 VALUES('other','minor',$1,$2,'agent','ErrorWatcher',$3,$1,$4,$5) RETURNING *`,[reason,proposal,kind,JSON.stringify(scope),JSON.stringify(replay)])).rows[0];
 });
}
