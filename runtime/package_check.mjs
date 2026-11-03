import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
export function digestFile(file){try{return createHash('sha256').update(fs.readFileSync(file)).digest('hex');}catch{return null;}}
export function packageValid(piece,dir) {
 try {
 const dest=path.join(dir,piece.id,'r'+piece.revision),p=JSON.parse(fs.readFileSync(path.join(dest,'package.json')));
 return p.content_id===piece.id&&p.revision===piece.revision&&p.post_text===piece.body&&(!piece.current_content_hash||p.content_hash===piece.current_content_hash)&&
 Object.keys(p.files).length>0&&Object.entries(p.files).every(([f,h])=>path.basename(f)===f&&digestFile(path.join(dest,f))===h);
 }catch{return false;}
}
