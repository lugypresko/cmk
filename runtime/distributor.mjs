import {tx} from './db.mjs';
function human(a){if(a?.type!=='human'||!a.name?.trim())throw Error('Explicit human confirmer required');}
export async function beginManual(db,content_id,account_ref,slot=null) {
 if(!account_ref?.trim())throw Error('account_ref required');
 return tx(db,async t=>{
 const p=(await t.query('SELECT *,content_hash(content_library) AS hash FROM content_library WHERE id=$1 FOR UPDATE',[content_id])).rows[0];
 if(!p||!['approved','scheduled'].includes(p.status)||p.edited_after_approval)throw Error('Current approved revision required');
 if(slot&&!(await t.query("SELECT 1 FROM rotation_slots WHERE id=$1 AND content_id=$2 AND status='confirmed'",[slot,content_id])).rows.length)throw Error('Slot must be human-confirmed');
 if((await t.query("SELECT 1 FROM publish_instances WHERE content_id=$1 AND account_ref=$2 AND state='unknown'",[content_id,account_ref])).rows.length)throw Error('D3: unknown outcome requires human resolution');
 let pi=(await t.query(`SELECT * FROM publish_instances WHERE content_id=$1 AND account_ref=$2 AND rotation_slot_id IS NOT DISTINCT FROM $3::uuid FOR UPDATE`,[content_id,account_ref,slot])).rows[0];
 if(!pi)pi=(await t.query(`INSERT INTO publish_instances(content_id,content_revision,sent_content_hash,channel,account_ref,rotation_slot_id,mode)
 VALUES($1,$2,$3,$4,$5,$6,'manual') RETURNING *`,[content_id,p.revision,p.hash,p.channel,account_ref,slot])).rows[0];
 if(!['queued','failed_retryable'].includes(pi.state))throw Error('D3: instance '+pi.state+'; no resend');
 const attempt=(await t.query(`INSERT INTO publish_attempts(publish_instance_id,attempt_no)
 SELECT $1,coalesce(max(attempt_no),0)+1 FROM publish_attempts WHERE publish_instance_id=$1 RETURNING *`,[pi.id])).rows[0];
 return {instance_id:pi.id,attempt_id:attempt.id,mode:'manual',instruction:'No post sent. Paste manually, then record URL or outcome.'};
 });
}
export async function recordOutcome(db,attempt_id,outcome,error_class=null) {
 if(!['unknown','failed_retryable','failed_final'].includes(outcome))throw Error('Use confirm URL for confirmed outcomes');
 const cls=outcome==='failed_retryable'?'rate_limit':outcome==='failed_final'?'validation':null;
 return tx(db,async t=>{
 const a=(await t.query('SELECT * FROM publish_attempts WHERE id=$1 FOR UPDATE',[attempt_id])).rows[0];
 if(!a||a.outcome!==null)throw Error('Attempt missing or already finished');
 await t.query('UPDATE publish_attempts SET outcome=$2,error_class=$3,finished_at=now() WHERE id=$1',[attempt_id,outcome==='unknown'?'unknown':'error',error_class||cls]);
 return (await t.query('SELECT * FROM publish_instances WHERE id=$1',[a.publish_instance_id])).rows[0];
 });
}
export async function confirmURL(db,id,url,actor) {
 human(actor);const u=new URL(url);
 if(u.protocol!=='https:'||!(u.hostname==='www.linkedin.com'||u.hostname==='linkedin.com')||!/^\/(posts|feed\/update)\//.test(u.pathname))throw Error('LinkedIn post HTTPS URL required');
 return tx(db,async t=>{
 const pi=(await t.query('SELECT * FROM publish_instances WHERE id=$1 FOR UPDATE',[id])).rows[0];
 if(!pi||!['sending','unknown'].includes(pi.state))throw Error('Instance not awaiting manual confirmation');
 const p=(await t.query('SELECT *,content_hash(content_library) AS hash FROM content_library WHERE id=$1 FOR UPDATE',[pi.content_id])).rows[0];
 if(p.hash!==pi.sent_content_hash||p.edited_after_approval)throw Error('Content changed since manual attempt; resolve explicitly');
 await t.query("UPDATE publish_attempts SET outcome='ok',verified_via='itay_manual',finished_at=now() WHERE publish_instance_id=$1 AND outcome IS NULL",[id]);
 await t.query("UPDATE publish_instances SET state='confirmed',external_url=$2,confirmed_by=$3,confirmed_at=now() WHERE id=$1",[id,url,actor.name]);
 await t.query("UPDATE content_library SET status='published',external_url=$2,published_at=now(),last_published_at=now(),times_published=times_published+1 WHERE id=$1",[pi.content_id,url]);
 if(pi.rotation_slot_id)await t.query("UPDATE rotation_slots SET status='published' WHERE id=$1",[pi.rotation_slot_id]);
 return {id,state:'confirmed',url};
 },actor);
}
