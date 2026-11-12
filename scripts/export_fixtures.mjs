// Export Guardian read-context from the local PGlite DB into guardian/fixtures/*.json
// (so the Python gates run with stdlib only). Read-only against the DB.
import { createRequire } from 'module';
import fs from 'fs';
const require = createRequire('/tmp/pgl/package.json');
const { PGlite } = await import(require.resolve('@electric-sql/pglite'));
const { pgcrypto } = await import(require.resolve('@electric-sql/pglite/contrib/pgcrypto'));
const root = new URL('..', import.meta.url).pathname;
const db = new PGlite(root + 'db/pglite', { extensions: { pgcrypto } });
const q = async (s) => (await db.query(s)).rows;
const out = {
  'checklist.json': (await q('SELECT body FROM cmk.guardian_checklists ORDER BY version DESC LIMIT 1'))[0].body,
  'format_specs.json': await q(`SELECT * FROM cmk.format_specs WHERE is_active ORDER BY format, channel, language`),
  'brand_voice.json': (await q(`SELECT * FROM cmk.brand_voice WHERE is_active`))[0],
  'icp_profile.json': (await q(`SELECT * FROM cmk.icp_profiles WHERE is_active ORDER BY priority LIMIT 1`))[0],
  'thresholds.json': (await q(`SELECT * FROM cmk.guardian_thresholds WHERE is_active`))[0],
  'approved_facts_db.json': {
    _note: 'Exported from local PGlite cmk.approved_facts. Approval state is taken from the DB at export time. FactGate only accepts status=approved AND confidentiality=public AND unexpired. No Stripe/proof facts exist.',
    exported_at: new Date().toISOString(),
    facts: await q(`SELECT id, fact_key, category, statement_en, statement_he, source_url, confidentiality::text, status::text,
                           approved_by, approved_at, valid_until, usage_scope FROM cmk.approved_facts ORDER BY fact_key`),
  },
};
for (const [f, v] of Object.entries(out)) fs.writeFileSync(root + 'guardian/fixtures/' + f, JSON.stringify(v, null, 2) + '\n');
console.log('wrote', Object.keys(out).join(', '));
await db.close();
