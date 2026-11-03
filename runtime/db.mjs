import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
export const root=fileURLToPath(new URL('../',import.meta.url));
const require=createRequire(process.env.PGLITE_FROM||'/tmp/pgl/package.json');
export async function openDB(dir=process.env.CMK_DB_DIR||path.join(root,'db/pglite')) {
 const {PGlite}=await import(require.resolve('@electric-sql/pglite'));
 const {pgcrypto}=await import(require.resolve('@electric-sql/pglite/contrib/pgcrypto'));
 return new PGlite(dir,{extensions:{pgcrypto}});
}
export const agent={type:'agent',name:'Codex',run:'phase-0-1'};
export async function tx(db,fn,actor=agent) {
 if(!['human','agent'].includes(actor.type)||!actor.name?.trim()||!actor.run) throw Error('actor identity required');
 return db.transaction(async t=>{
  await t.query("SELECT set_config('cmk.actor_type',$1,true),set_config('cmk.actor_name',$2,true),set_config('cmk.run_id',$3,true)",[actor.type,actor.name,actor.run]);
  await t.exec('SET LOCAL search_path=cmk,public');
  return fn(t);
 });
}
export async function journal(db,n,phase,notes) {
 const id=`J-20261103-${String(n).padStart(3,'0')}`;
 const filename=`journal/entries/2026-11-03_${String(n).padStart(3,'0')}_phase_${phase}.md`;
 const stamp=new Date().toISOString();
 await tx(db,t=>t.query(`INSERT INTO agent_journal(id,ts,agent,workflow,action,status,human_gate,notes,run_id,outputs)
 VALUES($1,$2,'Codex','ops',$3,'done','none',$4,'phase-0-1',$5) ON CONFLICT(id) DO NOTHING`,[id,stamp,`phase-${phase}`,notes,[filename]]));
 if(!fs.existsSync(path.join(root,filename))) fs.writeFileSync(path.join(root,filename),`---\nid: ${id}\nts: ${stamp}\nagent: Codex\nworkflow: ops\naction: phase-${phase}\nstatus: done\nhuman_gate: none\n---\n\n${notes}\n`);
}
