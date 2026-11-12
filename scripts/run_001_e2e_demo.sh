#!/usr/bin/env bash
# Local Run 001 demo (HE carousel Variant B only). Manual paste; this script never posts.
# Postgres gates for the same slice: migrations/012_e2e_chain_slice.sql
# (the grilled file was 006; 006–011 on this branch are already used).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/runs/001-human-gates/out"
cd "$ROOT"
cmd="${1:-help}"

case "$cmd" in
  build)
    python3 -m cmk_ops.carousel_render
    python3 - <<'PY'
from pathlib import Path
import json, re
from cmk_ops.canon import sha256_canon
root = Path('runs/001-human-gates'); out = root/'out'
he = (root/'linkedin_text_he.md').read_text(encoding='utf-8')
body = re.search(r'```text\n(.*?)```', he, re.S).group(1).strip()
body = re.sub(r'\n⟦STRIPE⟧.*?(?=\n\nצעד)', '', body, flags=re.S).strip()
hook = 'הסוכן סיים את ה-PR.\nואז הוא חיכה ל״מבט האחרון״ שלכם.'
cta = 'בתהליך של הצוות שלכם, איפה יושב האדם: בהתחלה ובסוף, או באמצע של כל שלב?'
qa = json.loads((out/'render_qa.json').read_text())
assets = [{'role':'carousel_pdf','sha256':qa['pdf_sha256']}] + [{'role':f"slide_{s['n']:02d}",'sha256':s['sha256']} for s in qa['slides']]
payload = {'run_id':'001-human-gates','variant':'B','channel':'linkedin','account':'itayfoyerstein','language':'he','formats':['text_post','carousel'],'text_post':{'hook':hook,'body':body,'cta':cta,'hashtags':[]},'assets':assets,'repeat_windows':{'exact_repeatable':False},'first_comment':None}
ph = sha256_canon(payload)
pkg = json.loads((out/'approval_package.json').read_text()) if (out/'approval_package.json').exists() else {}
# rewrite package
detail = [{'role':'carousel_pdf','path':qa['pdf'],'sha256':qa['pdf_sha256']}] + [{'role':f"slide_{s['n']:02d}",'path':s['path'],'sha256':s['sha256']} for s in qa['slides']]
pkg = {'status':'ready_for_human_approval','package_hash':ph,'payload':payload,'assets_detail':detail,'render_qa_pass':qa['render_qa']['pass'],'approval_timeout_hours':48,'owner':'Itay'}
(out/'approval_package.json').write_text(json.dumps(pkg, ensure_ascii=False, indent=2), encoding='utf-8')
state = {'run_id':'001-human-gates','variant':'B','package_hash':ph,'state':'awaiting_package_approval','history':[],'url':None,'verified_by':None}
(out/'publish_verify.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
print(ph)
PY
    echo "OK build → $OUT"
    ;;
  approve)
    python3 - <<PY
import json
from pathlib import Path
from datetime import datetime, timezone
p = Path('runs/001-human-gates/out')
pkg = json.loads((p/'approval_package.json').read_text())
pkg['status'] = 'approved'
pkg['approved_by'] = 'Itay'
pkg['approved_at'] = datetime.now().astimezone().isoformat()
(p/'approval_package.json').write_text(json.dumps(pkg, ensure_ascii=False, indent=2), encoding='utf-8')
st = json.loads((p/'publish_verify.json').read_text())
st['state'] = 'handed_for_paste'
st['history'].append({'to':'handed_for_paste','at':pkg['approved_at']})
(p/'publish_verify.json').write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding='utf-8')
print('approved', pkg['package_hash'][:16], '→ handed_for_paste')
PY
    ;;
  report)
    url="${2:?url required}"
    python3 - <<PY
import json,sys
from pathlib import Path
from datetime import datetime
url = "$url"
p = Path('runs/001-human-gates/out')
st = json.loads((p/'publish_verify.json').read_text())
assert st['state'] in ('handed_for_paste','reported_published'), st['state']
st['state'] = 'reported_published'
st['url'] = url
st['history'].append({'to':'reported_published','url':url,'at':datetime.now().astimezone().isoformat()})
(p/'publish_verify.json').write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding='utf-8')
print('reported_published', url)
PY
    ;;
  verify)
    python3 - <<PY
import json
from pathlib import Path
from datetime import datetime
p = Path('runs/001-human-gates/out')
st = json.loads((p/'publish_verify.json').read_text())
assert st['state'] == 'reported_published' and st.get('url'), st
st['state'] = 'verified'
st['verified_by'] = 'Itay'
st['history'].append({'to':'verified','at':datetime.now().astimezone().isoformat()})
(p/'publish_verify.json').write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding='utf-8')
(p/'measurement_stub.json').write_text(json.dumps({
  'windows':['24h','7d'],
  'fields':['impressions','reactions','substantive_comments','inbound_type'],
  'status':'awaiting_manual_entry',
  'learning_proposal':'draft_only_needs_approval'
}, ensure_ascii=False, indent=2), encoding='utf-8')
print('verified — exact-repeat may be marked; measurement stub ready')
PY
    ;;
  status)
    python3 - <<PY
import json
from pathlib import Path
p = Path('runs/001-human-gates/out')
for name in ['approval_package.json','publish_verify.json','render_qa.json','measurement_stub.json']:
    f = p/name
    if f.exists():
        d = json.loads(f.read_text())
        if name=='approval_package.json':
            print('package', d.get('status'), d.get('package_hash','')[:16])
        elif name=='publish_verify.json':
            print('publish', d.get('state'), d.get('url'))
        elif name=='render_qa.json':
            print('render_qa pass=', d['render_qa']['pass'], 'pdf=', d['pdf_sha256'][:16])
        else:
            print('measure', d.get('status'))
PY
    ;;
  *)
    echo "Usage: $0 {build|approve|report <url>|verify|status}"
    ;;
esac
