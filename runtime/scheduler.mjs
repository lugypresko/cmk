import {tx,root} from './db.mjs';
import {packageValid} from './package_check.mjs';
import path from 'node:path';
const humanRequired=a=>{if(a?.type!=='human'||!a.name?.trim())throw Error('Explicit human confirmer required');};
const isoDate=v=>{if(v==null||v==='')return null;if(v instanceof Date)return v.toISOString().slice(0,10);const m=String(v).match(/\d{4}-\d{2}-\d{2}/);return m?m[0]:null;};
const addDays=(iso,n)=>{const d=new Date(iso+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+Number(n));return d.toISOString().slice(0,10);};
const maxIso=(a,b)=>!a?b:!b?a:(a>b?a:b);
const hashList=v=>{if(v==null)return [];const j=typeof v==='string'?JSON.parse(v):v;return Array.isArray(j)?j.map(String).sort():[];};
const sameHashes=(a,b)=>{const x=hashList(a),y=hashList(b);return x.length===y.length&&x.every((v,i)=>v===y[i]);};
// Null when this piece may be scheduled. A reason refuses the repeat and does not revoke approval (D2).
export async function exactRepeatViolation(t,piece){
 if(!piece?.is_exact_repeatable)return null;
 const hash=piece.current_content_hash||piece.hash;
 if(piece.edited_after_approval||!hash||hash!==piece.repeat_approved_content_hash)return 'hash_mismatch';
 const assets=(await t.query(`SELECT coalesce(jsonb_agg(sha256 ORDER BY sha256),'[]'::jsonb) AS hashes
  FROM media_assets WHERE content_id=$1 AND content_revision=$2 AND qa_status='pass'`,[piece.id,piece.revision])).rows[0].hashes;
 if(!sameHashes(assets,piece.repeat_asset_hashes))return 'asset_hash_mismatch';
 const bad=(await t.query(`SELECT 1 FROM content_fact_refs f JOIN approved_facts a ON a.id=f.approved_fact_id
  WHERE f.content_id=$1 AND NOT (a.status='approved' AND a.confidentiality='public' AND (a.valid_until IS NULL OR a.valid_until>now()))`,[piece.id])).rows.length;
 if(bad)return 'fact_not_usable';
 return null;
}
export async function proposeSlots(db,{start_date,name='LinkedIn v0',package_dir=path.join(root,'packages'),constraints={}}, withinTransaction=false) {
 if(!/^\d{4}-\d{2}-\d{2}$/.test(start_date)||Number.isNaN(Date.parse(start_date)))throw Error('ISO start date required');
 const write=async t=>{
 const cs={same_core_same_channel_days:4,min_gap_minutes_same_channel:180,language_mix:{he:.5,en:.5},format_mix_max_share:.5,evergreen_max_share:.3,quiet_days:[],...constraints};
 if(cs.same_core_same_channel_days<4||cs.min_gap_minutes_same_channel<180||cs.format_mix_max_share>.5)throw Error('v0 constraints cannot be relaxed');
 const plan=(await t.query(`INSERT INTO rotation_plans(name,start_date,daily_caps,constraints,status)
 VALUES($1,$2,'{"linkedin":1}',$3,'draft') RETURNING *`,[name,start_date,JSON.stringify(cs)])).rows[0];
 const pool=(await t.query(`SELECT c.*,content_hash(c) AS current_content_hash FROM content_library c JOIN format_registry r ON r.format=c.format
 WHERE c.status='approved' AND c.channel='linkedin' AND r.v0_enabled AND NOT c.edited_after_approval
 AND NOT EXISTS(SELECT 1 FROM rotation_slots s JOIN rotation_plans p ON p.id=s.rotation_plan_id
 WHERE s.content_id=c.id AND p.status NOT IN ('completed','cancelled') AND s.status<>'skipped')
 AND NOT (c.is_exact_repeatable AND EXISTS(SELECT 1 FROM rotation_slots s
  WHERE s.content_id=c.id AND s.status IN ('filled','confirmed','published')))
 AND NOT EXISTS(SELECT 1 FROM content_fact_refs f JOIN approved_facts a ON a.id=f.approved_fact_id WHERE f.content_id=c.id AND (a.status<>'approved' OR a.confidentiality<>'public' OR a.valid_until<=now()))
 ORDER BY c.approved_at,c.id`)).rows.filter(p=>packageValid(p,package_dir));
 // Measurement ranking uses only observed aggregates; sparse cells have neutral signal.
 const perf=(await t.query(`SELECT c.core_asset_id, count(distinct c.id)::int AS n, sum(p.icp_conversations) AS conversations, sum(p.comments)::float/nullif(sum(p.impressions),0) AS rate
 FROM content_library c JOIN performance_logs p ON p.content_id=c.id AND p.window_label='14d' GROUP BY c.core_asset_id`)).rows;
 const signal=p=>{const r=perf.find(x=>x.core_asset_id===p.core_asset_id);return r?.n>=3?Math.min(1,Number(r.conversations||0)/r.n+Number(r.rate||0)):.5;};
 const rank=p=>.40*signal(p)+.25/(1+Math.max(0,(Date.now()-new Date(p.approved_at))/86400000))+.20*.5+.15*(p.icp_relevance_score/100);
 pool.sort((a,b)=>rank(b)-rank(a)||new Date(a.approved_at)-new Date(b.approved_at));
 const existing=(await t.query(`SELECT s.*,c.core_asset_id,(p.start_date+s.day-1)::text AS date FROM rotation_slots s JOIN rotation_plans p ON p.id=s.rotation_plan_id JOIN content_library c ON c.id=s.content_id WHERE s.status IN ('filled','confirmed','published')`)).rows;
 const planEnd=addDays(start_date,13);
 const blocked=[];
 const fresh=[];
 for(const p of pool){
  if(!p.is_exact_repeatable){fresh.push(p);continue;}
  const violation=await exactRepeatViolation(t,p);
  if(violation)blocked.push({content_id:p.id,reason:violation});
  else fresh.push(p);
 }
 // Exact repeats reuse the approved content_id. They are not a new revision.
 // Open-plan membership and the 4-day same-core gap do not exclude them; the repeat interval does.
 const exactRows=(await t.query(`SELECT c.*,content_hash(c) AS current_content_hash,
  coalesce((SELECT jsonb_agg(m.sha256 ORDER BY m.sha256) FROM media_assets m
   WHERE m.content_id=c.id AND m.content_revision=c.revision AND m.qa_status='pass'),'[]'::jsonb) AS current_asset_hashes,
  ((c.last_published_at AT TIME ZONE 'Asia/Jerusalem')::date)::text AS last_published_date,
  EXISTS(SELECT 1 FROM content_fact_refs f JOIN approved_facts a ON a.id=f.approved_fact_id
   WHERE f.content_id=c.id AND NOT (a.status='approved' AND a.confidentiality='public'
   AND (a.valid_until IS NULL OR a.valid_until>now()))) AS facts_blocked
  FROM content_library c JOIN format_registry r ON r.format=c.format
  WHERE c.is_exact_repeatable AND c.channel='linkedin' AND c.format IN ('text_post','carousel') AND r.v0_enabled
   AND c.status IN ('approved','scheduled','published')
  ORDER BY c.id`)).rows;
 const exact=[];
 for(const p of exactRows){
  const prior=existing.filter(e=>String(e.content_id)===String(p.id));
  if(!prior.length)continue;
  const last=maxIso(prior.map(e=>isoDate(e.date)).sort().at(-1)||null,isoDate(p.last_published_date));
  if(!last)continue;
  const due=addDays(last,Number(p.repeat_every_days)||14);
  if(due>planEnd)continue;
  const until=isoDate(p.repeat_until);
  if(until&&until<start_date)continue;
  if(!Number.isFinite(Number(p.max_repeats))||prior.length-1>=Number(p.max_repeats)||Number(p.repeats_done)>=Number(p.max_repeats)){
   blocked.push({content_id:p.id,reason:'max_repeats'});continue;
  }
  if(!until||due>until){blocked.push({content_id:p.id,reason:'repeat_until'});continue;}
  if(prior.some(e=>{const d=isoDate(e.date);return d>=due&&d<=planEnd;}))continue;
  let reason=null;
  if(p.edited_after_approval||p.current_content_hash!==p.repeat_approved_content_hash)reason='hash_mismatch';
  else if(!sameHashes(p.current_asset_hashes,p.repeat_asset_hashes))reason='asset_hash_mismatch';
  else if(p.facts_blocked)reason='fact_not_usable';
  else if(!packageValid(p,package_dir))reason='package';
  if(reason){blocked.push({content_id:p.id,reason});continue;}
  exact.push({...p,due,until,exactRepeat:true});
 }
 exact.sort((a,b)=>a.due.localeCompare(b.due)||String(a.id).localeCompare(String(b.id)));
 // Non-exact evergreen is listed for a new revision. This function does not create that row.
 const newRevision=(await t.query(`SELECT c.id FROM content_library c JOIN format_registry r ON r.format=c.format
  WHERE c.is_evergreen AND NOT c.is_exact_repeatable AND c.status='published' AND c.channel='linkedin'
   AND c.format IN ('text_post','carousel') AND r.v0_enabled AND c.last_published_at IS NOT NULL
   AND (c.last_published_at AT TIME ZONE 'Asia/Jerusalem')::date <= $1::date - GREATEST(coalesce(c.recycle_after_days,14),14)
  ORDER BY c.id`,[start_date])).rows.map(r=>r.id);
 const filled=[],counts={he:0,en:0,text_post:0,carousel:0};
 const mix=p=>counts[p.format]<Math.ceil(14*cs.format_mix_max_share)&&counts[p.language]<Math.ceil(14*cs.language_mix[p.language])+1;
 for(let day=1;day<=14;day++) {
 const date=new Date(start_date+'T12:00:00Z');date.setUTCDate(date.getUTCDate()+day-1);const iso=date.toISOString().slice(0,10);
 if(cs.quiet_days.includes(iso))continue;
 const occupied=(await t.query(`SELECT 1 FROM rotation_slots s JOIN rotation_plans p ON p.id=s.rotation_plan_id
 WHERE p.start_date+(s.day-1)=$1::date AND s.channel='linkedin' AND s.status IN ('filled','confirmed','published')`,[iso])).rows.length;
 const exactPiece=occupied?null:exact.find(p=>iso>=p.due&&iso<=p.until&&!filled.some(f=>String(f.p.id)===String(p.id))&&mix(p));
 const piece=exactPiece||(occupied?null:fresh.find(p=>
  (!p.is_exact_repeatable||!isoDate(p.repeat_until)||iso<=isoDate(p.repeat_until))&&
  !filled.some(f=>f.p.id===p.id)&&
  !filled.some(f=>f.p.core_asset_id===p.core_asset_id&&day-f.day<cs.same_core_same_channel_days)&&
  !existing.some(e=>e.core_asset_id===p.core_asset_id&&Math.abs((Date.parse(iso)-Date.parse(e.date))/86400000)<cs.same_core_same_channel_days)&&
  mix(p)));
 const rationale=!piece?'No eligible candidate / day occupied':piece.exactRepeat
  ?'Exact repeat of approved revision; same content_id and hash; human confirmation required'
  :'Approved packaged revision; v0 cap; human confirmation required';
 const slot=(await t.query(`INSERT INTO rotation_slots(rotation_plan_id,day,channel,format,language,local_time,content_id,status,rationale)
 VALUES($1,$2,'linkedin',$3,$4,'08:30',$5,$6,$7) RETURNING *`,
 [plan.id,day,piece?.format||null,piece?.language||null,piece?.id||null,piece?'filled':'open',rationale])).rows[0];
 if(piece){filled.push({p:piece,day,slot});counts[piece.language]++;counts[piece.format]++;}
 }
 return {plan,filled:filled.map(f=>f.slot),open:14-filled.length,blocked_exact_repeats:blocked,new_revision_candidates:newRevision};
 };
 return withinTransaction?write(db):tx(db,write);
}
export async function confirmSlot(db,id,actor,package_dir=path.join(root,'packages')) {
 humanRequired(actor);
 return tx(db,async t=>{
 // Serialize confirmation across plans, not merely within a single slot.
 await t.exec('LOCK TABLE rotation_slots IN SHARE ROW EXCLUSIVE MODE');
 const s=(await t.query(`SELECT s.*,p.start_date,p.constraints FROM rotation_slots s JOIN rotation_plans p ON p.id=s.rotation_plan_id WHERE s.id=$1 FOR UPDATE OF s`,[id])).rows[0];
 if(!s||s.status!=='filled')throw Error('Slot is not a draft proposal');
 const p=(await t.query('SELECT *,content_hash(content_library) AS current_content_hash FROM content_library WHERE id=$1 FOR UPDATE',[s.content_id])).rows[0];
 const violation=p&&await exactRepeatViolation(t,p);
 if(violation)throw Error('Exact repeat blocked: '+violation);
 const repeatable=p?.is_exact_repeatable&&['approved','scheduled','published'].includes(p.status);
 if(!p||p.edited_after_approval||!packageValid(p,package_dir)||!(p.status==='approved'||repeatable))throw Error('Approved current package required');
 if(p.is_exact_repeatable){
  const slotDate=addDays(isoDate(s.start_date),s.day-1);
  const until=isoDate(p.repeat_until);
  if(!until||slotDate>until)throw Error('Exact repeat blocked: repeat_until');
  const prior=(await t.query(`SELECT count(*)::int AS n, max(z.start_date+(s2.day-1))::text AS last
   FROM rotation_slots s2 JOIN rotation_plans z ON z.id=s2.rotation_plan_id
   WHERE s2.content_id=$1 AND s2.id<>$2 AND s2.status IN ('filled','confirmed','published')`,[p.id,id])).rows[0];
  if(Number(prior.n)>=1){
   if(Number(prior.n)>Number(p.max_repeats)||Number(p.repeats_done)>=Number(p.max_repeats))throw Error('Exact repeat blocked: max_repeats');
   if(slotDate<addDays(isoDate(prior.last),Number(p.repeat_every_days)||14))throw Error('Exact repeat blocked: interval');
  }
 }
 const at=(await t.query(`SELECT (($1::date+($2::int-1))+$3::time) AT TIME ZONE 'Asia/Jerusalem' AS at`,[s.start_date,s.day,s.local_time])).rows[0].at;
 const conflict=(await t.query(`SELECT 1 FROM rotation_slots x JOIN rotation_plans z ON z.id=x.rotation_plan_id
 WHERE x.id<>$1 AND x.channel='linkedin' AND x.status IN ('confirmed','published') AND z.start_date+(x.day-1)=$2::date+($3::int-1)`,[id,s.start_date,s.day])).rows.length;
 if(conflict)throw Error('LinkedIn daily cap 1 exceeded');
 await t.query("UPDATE rotation_slots SET status='confirmed',confirmed_by=$2,confirmed_at=now() WHERE id=$1",[id,actor.name]);
 await t.query("UPDATE content_library SET status='scheduled',scheduled_at=$2,rotation_plan_id=$3,rotation_slot_id=$4,rotation_slot=$5 WHERE id=$1",[p.id,at,s.rotation_plan_id,id,s.day]);
 return {id,scheduled_at:at};
 },actor);
}
