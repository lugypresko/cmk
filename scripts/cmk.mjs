#!/usr/bin/env node
// Explicit commands only. There is no auto-publish adapter.
import fs from 'node:fs';
import path from 'node:path';
import {openDB,root,journal} from '../runtime/db.mjs';
import {enqueue,run,resumeHuman} from '../runtime/orchestrator.mjs';
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
 case 'run': result=await run(db,required('id'));break;
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
 default:throw Error('Commands: enqueue run resume qa package measure import-past propose-slots confirm-slot begin-manual outcome posted-url error-watch status');
 }
 console.log(JSON.stringify(result,null,2));
 // Each CLI invocation is mirrored in an append-only entry with a unique increasing suffix.
 const n=Math.max(21,...fs.readdirSync(path.join(root,'journal/entries')).map(f=>Number(f.match(/^2026-11-03_(\d+)_/)?.[1]||0)))+1;
 await journal(db,n,'runtime_cli',`${op}: completed; see authoritative DB rows. Human approvals were never inferred.`);
}catch(e){console.error(e.message);process.exitCode=1;}finally{if(db)await db.close();}
