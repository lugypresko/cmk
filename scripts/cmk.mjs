#!/usr/bin/env node
// Explicit commands only. There is no auto-publish adapter.
import fs from 'node:fs';
import {config,executionMode} from '../llm/client.mjs';
import {planResearch,collectResearch} from '../research/runtime.mjs';
import path from 'node:path';
import {openDB,root,journal} from '../runtime/db.mjs';
import {enqueue,run,resumeHuman,preview,retryHuman} from '../runtime/orchestrator.mjs';
import {qa,buildPackage,importMeasurement,importPast} from '../runtime/production.mjs';
import {proposeSlots,confirmSlot} from '../runtime/scheduler.mjs';
import {beginManual,recordOutcome,confirmURL} from '../runtime/distributor.mjs';
import {proposeReplay} from '../runtime/error_watcher.mjs';
const [op,...args]=process.argv.slice(2);
const value=k=>{const i=args.indexOf('--'+k);return i<0?null:args[i+1];};
const required=k=>{const v=value(k);if(!v||v.startsWith('--'))throw Error('--'+k+' required');return v;};
const read=k=>JSON.parse(fs.readFileSync(required(k),'utf8'));
const human=()=>({type:'human',name:required('confirmer'),run:'manual-cli-'+Date.now()});
const package_dir=value('packages')||path.join(root,'packages');
let db;
try {
 db=await openDB();let result;
 switch(op) {
 case 'enqueue': result=await enqueue(db,required('kind'),read('input'));break;
 case 'start':result=await enqueue(db,'core',{idea:value('idea')||'Find an evidenced content direction from the supplied research.',language:value('language')||'he',package_dir,...(value('research-id')?{research_run_id:value('research-id')}:{})});break;
 case 'research-plan':result=await planResearch(db,{key:value('profile')||undefined});break;
 case 'research-import':result=await collectResearch(db,{key:value('profile')||undefined,imported:read('file')});break;
 case 'research-collect': {
 if(!args.includes('--allow-source-calls')){result=await planResearch(db,{key:value('profile')||undefined});break;}
 result=await collectResearch(db,{key:value('profile')||undefined,online:true});break;
 }
 case 'research-status':result=(await db.query('SELECT id,provider,state,budget_microusd,created_at,completed_at,coverage FROM cmk.research_runs WHERE id=$1',[required('id')])).rows;break;
 case 'research-agents':result=(await db.query('SELECT role,state,prompt_version_id,error_code,started_at,completed_at,output FROM cmk.research_agent_tasks WHERE work_item_id=$1 ORDER BY started_at',[required('id')])).rows;break;
 case 'run': {
  const mode=executionMode(args);
  if(mode==='--allow-paid') {
   if(!config(process.env,true).enabled)throw Error('CMK_LLM_PAID_CALLS_ENABLED=true also required');
   const w=(await db.query('SELECT context FROM cmk.work_items WHERE id=$1',[required('id')])).rows[0];
   if(!w)throw Error('work item not found');
   if(['research','core','piece'].some(k=>w.context[k]))throw Error('Paid mode refuses fixture payloads; create a live work item');
   result=await run(db,required('id'),undefined,{allowPaid:true});
  }else if(mode==='--fixture'||mode==='--offline')result=await run(db,required('id'));
  else result=await preview(db,required('id'));
  break;
 }
 case 'retry':result=await retryHuman(db,required('id'),human());break;
 case 'multiply': {
  const w=(await db.query("SELECT * FROM cmk.work_items WHERE id=$1 AND kind='core'",[required('id')])).rows[0];
  if(!w?.subject_id)throw Error('Core work item has no Core yet');
  const core=(await db.query("SELECT status FROM cmk.core_assets WHERE id=$1",[w.subject_id])).rows[0];
  if(core?.status!=='approved')throw Error('human_gate:approve_core');
  result=await enqueue(db,'derivative',{core_id:w.subject_id,format:'text_post',language:value('language')||'he',package_dir},null,w.id);
  break;
 }
 case 'llm-status':result=(await db.query(`SELECT r.id,r.budget_microusd,c.id AS call_id,c.state,c.model,c.charged_microusd,c.error_code
  FROM cmk.llm_runs r LEFT JOIN cmk.llm_calls c ON c.run_id=r.id WHERE r.id=(SELECT run_id FROM cmk.work_items WHERE id=$1) ORDER BY c.created_at`,[required('id')])).rows;break;
 case 'resume': result=await resumeHuman(db,required('id'),human());break;
 case 'qa': result=await qa(db,required('id'),path.resolve(required('file')),read('alt'));break;
 case 'package': result=await buildPackage(db,required('id'),package_dir,args.includes('--allow-edited')?human():null);break;
 case 'measure': {
 const manual={};for(const k of ['icp_conversations','time_saved_minutes'])if(value(k)!==null)manual[k]=Number(value(k));
 if(Object.keys(manual).length&&!args.includes('--manual'))throw Error('--manual required for human success metrics');
 result=await importMeasurement(db,required('id'),required('file'),required('window'),required('captured-at'),manual,Object.keys(manual).length?human():null);break;
 }
 case 'import-past':result=await importPast(db,required('file'),value('language'));break;
 case 'propose-slots':result=await proposeSlots(db,{start_date:required('start'),package_dir});break;
 case 'confirm-slot':result=await confirmSlot(db,required('id'),human(),package_dir);break;
 case 'begin-manual':result=await beginManual(db,required('id'),required('account'),value('slot'));break;
 case 'outcome':result=await recordOutcome(db,required('attempt'),required('outcome'));break;
 case 'posted-url':result=await confirmURL(db,required('id'),required('url'),human());break;
 case 'error-watch':result=await proposeReplay(db,read('input'));break;
 case 'status':result=(await db.query('SELECT id,kind,state,step,blocked_on,stop_reason FROM cmk.work_items ORDER BY created_at')).rows;break;
 default:throw Error('Commands: research-plan research-import research-collect research-status research-agents start enqueue run retry multiply llm-status resume qa package measure import-past propose-slots confirm-slot begin-manual outcome posted-url error-watch status');
 }
 console.log(JSON.stringify(result,null,2));
 // Each CLI invocation is mirrored in an append-only entry with a unique increasing suffix.
 const n=Math.max(21,...fs.readdirSync(path.join(root,'journal/entries')).map(f=>Number(f.match(/^\d{4}-\d{2}-\d{2}_(\d+)_/)?.[1]||0)))+1;
 await journal(db,n,'runtime_cli',`${op}: completed; see authoritative DB rows. Human approvals were never inferred.`);
}catch(e){console.error(e.message);process.exitCode=1;}finally{if(db)await db.close();}
