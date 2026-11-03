// Read-only query helper against the local PGlite DB: node scripts/q.mjs "SELECT ..."
import { createRequire } from 'module';
const require = createRequire('/tmp/pgl/package.json');
const { PGlite } = await import(require.resolve('@electric-sql/pglite'));
const { pgcrypto } = await import(require.resolve('@electric-sql/pglite/contrib/pgcrypto'));
const db = new PGlite(new URL('../db/pglite', import.meta.url).pathname, { extensions: { pgcrypto } });
await db.exec('BEGIN READ ONLY');
try { const r = await db.query(process.argv[2]); console.log(JSON.stringify(r.rows, null, 1)); }
catch (e) { console.error('ERR', e.message); process.exitCode = 1; }
await db.exec('ROLLBACK');
await db.close();
