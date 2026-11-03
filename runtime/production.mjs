import {spawnSync} from 'node:child_process';
import {tx,root} from './db.mjs';
export function python(op,args) {
 const p=spawnSync(process.env.CMK_PYTHON||'python3',['-m','runtime.files'],{cwd:root,input:JSON.stringify({op,...args}),encoding:'utf8'});
 if(p.status!==0) throw Error(p.stderr||p.stdout);return JSON.parse(p.stdout);
}
export async function qa(db,id,file,alt_text) {
 return tx(db,async t=>{
  const piece=(await t.query('SELECT * FROM content_library WHERE id=$1',[id])).rows[0];
  if(!piece)throw Error('unknown piece');
  const spec=(await t.query('SELECT * FROM format_specs WHERE id=$1',[piece.format_spec_id])).rows[0];
  const report=python('render_qa',{path:file,piece,alt_text,spec});
  if(!report.sha256)throw Error('File cannot be read');
  const fs=await import('node:fs');
  await t.query(`INSERT INTO media_assets(content_id,content_revision,kind,storage_uri,sha256,bytes,source,qa_status,qa_report,qa_checked_at,page_count)
   VALUES($1,$2,'pdf',$3,$4,$5,'own',$6,$7,now(),$8)
   ON CONFLICT(content_id,content_revision,storage_uri) DO UPDATE SET sha256=excluded.sha256,qa_status=excluded.qa_status,
   qa_report=excluded.qa_report,qa_checked_at=now(),bytes=excluded.bytes,page_count=excluded.page_count`,
   [id,piece.revision,file,report.sha256,fs.statSync(file).size,report.status,JSON.stringify(report),report.page_count||null]);
  return report;
 });
}
export async function buildPackage(db,id,out_root,actor=null) {
 return tx(db,async t=>{
 const piece=(await t.query('SELECT * FROM content_library WHERE id=$1',[id])).rows[0];
 const assets=(await t.query('SELECT * FROM media_assets WHERE content_id=$1 AND content_revision=$2',[id,piece.revision])).rows;
 if(actor && actor.type!=='human')throw Error('Human flag requires human actor');
 return python('package',{piece,out_root,assets,allow_edited_by:actor?.name||null});
 });
}
export async function importMeasurement(db,id,file,window,captured,manual={},actor=null) {
 const parsed=python('linkedin_xlsx',{path:file});
 if(Object.keys(manual).some(k=>!['icp_conversations','time_saved_minutes'].includes(k)))throw Error('manual fields restricted');
 if(Object.keys(manual).length && (!actor||actor.type!=='human'))throw Error('Human metrics require confirmer');
 for(const v of Object.values(manual))if(!Number.isInteger(v)||v<0)throw Error('Invalid manual metric');
 return tx(db,async t=>{
 const p=(await t.query('SELECT * FROM content_library WHERE id=$1',[id])).rows[0];
 if(!p||p.external_url!==parsed.url)throw Error('Post URL does not match content mapping');
 const cols=Object.keys(parsed.metrics),vals=Object.values(parsed.metrics);
 await t.query(`INSERT INTO performance_logs(content_id,window_label,source,captured_at,icp_conversations,time_saved_minutes,confirmed_by,${cols.join(',')})
 VALUES($1,$2,'import',$3,$4,$5,$6,${vals.map((_,i)=>'$'+(i+7)).join(',')})
 ON CONFLICT(content_id,window_label,source) WHERE content_id IS NOT NULL AND window_label IS NOT NULL
 DO UPDATE SET captured_at=excluded.captured_at,${cols.map(c=>`${c}=excluded.${c}`).join(',')},
 icp_conversations=coalesce(excluded.icp_conversations,performance_logs.icp_conversations),
 time_saved_minutes=coalesce(excluded.time_saved_minutes,performance_logs.time_saved_minutes),
 confirmed_by=coalesce(excluded.confirmed_by,performance_logs.confirmed_by)`,
 [id,window,captured,manual.icp_conversations??null,manual.time_saved_minutes??null,actor?.name||null,...vals]);
 return parsed;
 },actor||undefined);
}
export async function importPast(db,file,language) {
 const rows=python('past_posts',{path:file,language});
 return tx(db,async t=>{
 for(const r of rows) {
 if(!['text_post','carousel'].includes(r.format))throw Error('disabled format');
 await t.query(`INSERT INTO past_content(body,language,url,external_post_id,format,channel,notes)
 SELECT $1,$2,$3,$4,$5,'linkedin',$6 WHERE NOT EXISTS(SELECT 1 FROM past_content WHERE body=$1 AND language=$2::cmk.lang_code)`,
 [r.body,r.language,r.url,r.external_post_id,r.format,r.notes]);
 }return {rows:rows.length};
 });
}
