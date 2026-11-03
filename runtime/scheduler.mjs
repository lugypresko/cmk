import {tx,root} from './db.mjs';
import {packageValid} from './package_check.mjs';
import path from 'node:path';
const humanRequired=a=>{if(a?.type!=='human'||!a.name?.trim())throw Error('Explicit human confirmer required');};
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
 AND NOT EXISTS(SELECT 1 FROM content_fact_refs f JOIN approved_facts a ON a.id=f.approved_fact_id WHERE f.content_id=c.id AND (a.status<>'approved' OR a.confidentiality<>'public' OR a.valid_until<=now()))
 ORDER BY c.approved_at,c.id`)).rows.filter(p=>packageValid(p,package_dir));
 // Measurement ranking uses only observed aggregates; sparse cells have neutral signal.
 const perf=(await t.query(`SELECT c.core_asset_id, count(distinct c.id)::int AS n, sum(p.icp_conversations) AS conversations, sum(p.comments)::float/nullif(sum(p.impressions),0) AS rate
 FROM content_library c JOIN performance_logs p ON p.content_id=c.id AND p.window_label='14d' GROUP BY c.core_asset_id`)).rows;
 const signal=p=>{const r=perf.find(x=>x.core_asset_id===p.core_asset_id);return r?.n>=3?Math.min(1,Number(r.conversations||0)/r.n+Number(r.rate||0)):.5;};
 const rank=p=>.40*signal(p)+.25/(1+Math.max(0,(Date.now()-new Date(p.approved_at))/86400000))+.20*.5+.15*(p.icp_relevance_score/100);
 pool.sort((a,b)=>rank(b)-rank(a)||new Date(a.approved_at)-new Date(b.approved_at));
 const existing=(await t.query(`SELECT s.*,c.core_asset_id,(p.start_date+s.day-1)::text AS date FROM rotation_slots s JOIN rotation_plans p ON p.id=s.rotation_plan_id JOIN content_library c ON c.id=s.content_id WHERE s.status IN ('filled','confirmed','published')`)).rows;
 // Greedy deterministic selection: human-approved candidates only. No auto-recycling.
 const filled=[],counts={he:0,en:0,text_post:0,carousel:0};
 for(let day=1;day<=14;day++) {
 const date=new Date(start_date+'T12:00:00Z');date.setUTCDate(date.getUTCDate()+day-1);const iso=date.toISOString().slice(0,10);
 if(cs.quiet_days.includes(iso))continue;
 const occupied=(await t.query(`SELECT 1 FROM rotation_slots s JOIN rotation_plans p ON p.id=s.rotation_plan_id
 WHERE p.start_date+(s.day-1)=$1::date AND s.channel='linkedin' AND s.status IN ('filled','confirmed','published')`,[iso])).rows.length;
 const piece=occupied?null:pool.find(p=>!filled.some(f=>f.p.id===p.id)&&
 !filled.some(f=>f.p.core_asset_id===p.core_asset_id&&day-f.day<cs.same_core_same_channel_days)&&
 !existing.some(e=>e.core_asset_id===p.core_asset_id&&Math.abs((Date.parse(iso)-Date.parse(e.date))/86400000)<cs.same_core_same_channel_days)&&
 counts[p.format]<Math.ceil(14*cs.format_mix_max_share)&&counts[p.language]<Math.ceil(14*cs.language_mix[p.language])+1);
 const slot=(await t.query(`INSERT INTO rotation_slots(rotation_plan_id,day,channel,format,language,local_time,content_id,status,rationale)
 VALUES($1,$2,'linkedin',$3,$4,'08:30',$5,$6,$7) RETURNING *`,
 [plan.id,day,piece?.format||null,piece?.language||null,piece?.id||null,piece?'filled':'open',piece?'Approved packaged revision; v0 cap; human confirmation required':'No eligible candidate / day occupied'])).rows[0];
 if(piece){filled.push({p:piece,day,slot});counts[piece.language]++;counts[piece.format]++;}
 }
 return {plan,filled:filled.map(f=>f.slot),open:14-filled.length};
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
 if(p?.status!=='approved'||p.edited_after_approval||!packageValid(p,package_dir))throw Error('Approved current package required');
 const at=(await t.query(`SELECT (($1::date+($2::int-1))+$3::time) AT TIME ZONE 'Asia/Jerusalem' AS at`,[s.start_date,s.day,s.local_time])).rows[0].at;
 const conflict=(await t.query(`SELECT 1 FROM rotation_slots x JOIN rotation_plans z ON z.id=x.rotation_plan_id
 WHERE x.id<>$1 AND x.channel='linkedin' AND x.status IN ('confirmed','published') AND z.start_date+(x.day-1)=$2::date+($3::int-1)`,[id,s.start_date,s.day])).rows.length;
 if(conflict)throw Error('LinkedIn daily cap 1 exceeded');
 await t.query("UPDATE rotation_slots SET status='confirmed',confirmed_by=$2,confirmed_at=now() WHERE id=$1",[id,actor.name]);
 await t.query("UPDATE content_library SET status='scheduled',scheduled_at=$2,rotation_plan_id=$3,rotation_slot_id=$4,rotation_slot=$5 WHERE id=$1",[p.id,at,s.rotation_plan_id,id,s.day]);
 return {id,scheduled_at:at};
 },actor);
}
