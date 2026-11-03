// CMK Phase 0 — apply schema + migrations 002..011 to a persistent local PGlite DB,
// then run smoke tests. ON_ERROR_STOP semantics: first failure exits non-zero.
// Usage: NODE_PATH=/tmp/pgl/node_modules node scripts/apply_all.mjs [--fresh]
// Local PGlite only — this is NOT a hosted / production Postgres.
import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(process.env.PGLITE_FROM || '/tmp/pgl/package.json');
const { PGlite } = await import(require.resolve('@electric-sql/pglite'));
const { pgcrypto } = await import(require.resolve('@electric-sql/pglite/contrib/pgcrypto'));

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DB_DIR = path.join(ROOT, 'db', 'pglite');
if (process.argv.includes('--fresh')) fs.rmSync(DB_DIR, { recursive: true, force: true });
fs.mkdirSync(DB_DIR, { recursive: true });

const db = new PGlite(DB_DIR, { extensions: { pgcrypto } });
const results = [];
await db.exec("SET cmk.actor_type='agent'; SET cmk.actor_name='migration-runner'; SET cmk.run_id='local-apply';");
const step = async (label, file, { optional = false } = {}) => {
  const p = path.join(ROOT, file);
  try {
    const r = await db.exec(fs.readFileSync(p, 'utf8'));
    results.push({ label, file, ok: true });
    console.log(`PASS  ${label.padEnd(8)} ${file}`);
    return r;
  } catch (e) {
    results.push({ label, file, ok: false, error: e.message });
    console.log(`FAIL  ${label.padEnd(8)} ${file}\n      ${e.message}`);
    if (!optional) { await db.close(); summary(); process.exit(1); }
  }
};
const summary = () => {
  const bad = results.filter(r => !r.ok);
  console.log(`\n== ${results.length - bad.length}/${results.length} steps passed` + (bad.length ? `; FAILED: ${bad.map(b => b.file).join(', ')}` : ''));
  console.log(`== DB: ${DB_DIR} (local PGlite, persistent)`);
};

// Idempotence: if schema already exists, skip schema.sql (it is not re-runnable), still re-run migrations (idempotent).
const exists = (await db.query(`SELECT to_regclass('cmk.content_library') IS NOT NULL AS e`)).rows[0].e;
if (!exists) await step('schema', 'schema.sql');
else { console.log('SKIP  schema   schema.sql (already applied in this DB)'); }
const migApplied = async (n) => (await db.query(`SELECT to_regclass($1) IS NOT NULL AS e`, [n])).rows[0].e;
// 002/003 are not guaranteed re-runnable; apply only when absent.
for (const [label, file, marker] of [
  ['002', 'migrations/002_spec_formats.sql', null],
  ['003', 'migrations/003_format_specs_seed.sql', null],
  ['004', 'migrations/004_agent_journal.sql', 'cmk.agent_journal'],
  ['005', 'migrations/005_critique_alignment.sql', 'cmk.work_items'],
]) {
  if (exists && (marker ? await migApplied(marker) : true) && label !== '005') { console.log(`SKIP  ${label.padEnd(8)} ${file} (already applied)`); continue; }
  await step(label, file);
}
// New numbered migrations are tracked individually, never inferred from unrelated tables.
await db.exec('CREATE TABLE IF NOT EXISTS cmk.runtime_migrations (filename text PRIMARY KEY, applied_at timestamptz DEFAULT now())');
for (const file of fs.readdirSync(path.join(ROOT, 'migrations')).filter(f => /^\d{3}_.*\.sql$/.test(f) && Number(f.slice(0,3))>=6).sort()) {
  if ((await db.query('SELECT 1 FROM cmk.runtime_migrations WHERE filename=$1',[file])).rows.length) continue;
  await step(file.slice(0,3), 'migrations/' + file);
  await db.transaction(async t=>{
    await t.exec("SET LOCAL cmk.actor_type='agent'; SET LOCAL cmk.actor_name='migration-runner'; SET LOCAL cmk.run_id='local-apply';");
    await t.query('INSERT INTO cmk.runtime_migrations(filename) VALUES ($1)',[file]);
  });
}
// Tests run inside a transaction and are rolled back so the durable DB stays clean.
for (const [label, file] of [['test23', 'migrations/test_002_003.sql'], ['test5', 'migrations/test_005.sql'], ['test11', 'migrations/test_011.sql']]) {
  const sql = fs.readFileSync(path.join(ROOT, file), 'utf8');
  try {
    await db.exec('BEGIN;'); await db.exec(sql); await db.exec('ROLLBACK;');
    results.push({ label, file, ok: true }); console.log(`PASS  ${label.padEnd(8)} ${file} (rolled back)`);
  } catch (e) {
    try { await db.exec('ROLLBACK;'); } catch {}
    results.push({ label, file, ok: false, error: e.message }); console.log(`FAIL  ${label.padEnd(8)} ${file}\n      ${e.message}`);
  }
}
const counts = (await db.query(`SELECT
  (SELECT count(*) FROM cmk.format_specs) AS format_specs,
  (SELECT count(*) FROM cmk.work_transitions) AS work_transitions,
  (SELECT count(*) FROM cmk.content_library) AS content_library,
  (SELECT count(*) FROM information_schema.tables WHERE table_schema='cmk') AS cmk_tables`)).rows[0];
console.log('== counts', JSON.stringify(counts));
await db.close();
summary();
process.exit(results.every(r => r.ok) ? 0 : 1);
