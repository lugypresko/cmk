// Restore append-only Markdown journal mirrors after --fresh (never updates existing rows).
import fs from 'node:fs';
import path from 'node:path';
import {openDB,tx,root} from '../runtime/db.mjs';
const db=await openDB();
try {
 for(const file of fs.readdirSync(path.join(root,'journal/entries')).filter(f=>f.endsWith('.md'))) {
 const text=fs.readFileSync(path.join(root,'journal/entries',file),'utf8');
 const field=k=>text.match(new RegExp('^'+k+':\\s*(.+)$','m'))?.[1]?.replace(/^['"]|['"]$/g,'');
 const sourceId=field('id');if(!sourceId)continue;
 const match=file.match(/^(\d{4})-(\d{2})-(\d{2})_(\d+)_/);
 const id=/^J-\d{8}-\d{3,}$/.test(sourceId)?sourceId:(match?`J-${match[1]}${match[2]}${match[3]}-${match[4]}`:null);
 if(!id)continue;
 const stamp=field('ts');if(!stamp||Number.isNaN(Date.parse(stamp)))continue;
 await tx(db,t=>t.query(`INSERT INTO agent_journal(id,ts,agent,workflow,action,status,human_gate,notes,run_id,outputs)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,'journal-sync',$9) ON CONFLICT(id) DO NOTHING`,
 [id,stamp,field('agent')||'Codex',field('workflow')||'ops',field('action')||file,field('status')||'done',field('human_gate')||'none',
 text.split('---').slice(2).join('---').trim(),['journal/entries/'+file]]));
 }
 console.log('Journal mirrored without updates');
}finally{await db.close();}
