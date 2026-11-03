"""File-only production checks and import parsing. No approval side effects."""
import hashlib
import json
import re
import unicodedata
from pathlib import Path


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def normalized(text):
    return re.sub(r'\s+', '', unicodedata.normalize('NFKC', text))


def render_qa(path, piece, alt_text, spec=None):
    import fitz
    checks = {'opens': False, 'page_count': False, 'text_match': False,
              'rtl': piece.get('language') != 'he', 'fonts_embedded': False,
              'alt_text': bool(alt_text) and all(str(a).strip() for a in alt_text), 'dimensions': False}
    report = {'checks': checks, 'status': 'fail', 'sha256': None}
    try:
        report['sha256'] = digest(path)
        with fitz.open(path) as doc:
            checks['opens'] = not doc.is_encrypted and len(doc) > 0
            expected = [((s.get('headline') or '')+'\n'+(s.get('text') or '')).strip()
                        for s in piece.get('slides') or []] or [piece['body']]
            checks['page_count'] = len(doc) == len(expected)
            checks['alt_text'] &= len(alt_text) == len(expected)
            texts = [p.get_text() for p in doc]
            # PDF may encode visual order. Reverse each Hebrew line only, never the whole page.
            def match(a, b):
                return normalized(a) == normalized(b) or (piece.get('language') == 'he' and
                    normalized('\n'.join(line[::-1] if re.search('[א-ת]',line) else line for line in a.splitlines())) == normalized(b))
            checks['text_match'] = len(texts)==len(expected) and all(match(a,b) for a,b in zip(texts,expected))
            spec = spec or {}
            checks['dimensions'] = all(p.rect.width > 0 and p.rect.height > 0 and
                (not spec.get('aspect_ratio') or abs(p.rect.width/p.rect.height - float(spec['aspect_ratio'])) < .02) for p in doc)
            used={span['font'] for p in doc for block in p.get_text('dict')['blocks'] for line in block.get('lines',[]) for span in line['spans']}
            font_records=[f for p in doc for f in p.get_fonts() if f[3].split('+')[-1] in used]
            checks['fonts_embedded'] = bool(font_records) and all(doc.extract_font(f[0])[3] for f in font_records)
            if piece.get('language') == 'he':
                # Visual PDF Hebrew runs must read right-to-left, or expose logical RTL direction.
                runs=[]
                for p in doc:
                    for block in p.get_text('rawdict')['blocks']:
                        for line in block.get('lines',[]):
                            for span in line['spans']:
                                chars=[c for c in span['chars'] if re.search('[א-ת]',c['c'])]
                                if len(chars)>1:
                                    text=''.join(c['c'] for c in chars)
                                    expected_chars=''.join(re.findall('[א-ת]', '\n'.join(expected)))
                                    direction=chars[0]['origin'][0] > chars[-1]['origin'][0]
                                    runs.append((direction and text in expected_chars) or (not direction and text[::-1] in expected_chars))
                checks['rtl'] = bool(runs) and all(runs)
            report['page_count'] = len(doc)
    except Exception as e:
        report['error'] = str(e)
    report['status'] = 'pass' if all(checks.values()) else 'fail'
    return report


def package(piece, out_root, assets=(), allow_edited_by=None):
    import shutil
    if piece['status'] != 'approved' or not piece.get('approved_by') or not piece.get('approved_at'):
        raise ValueError('Package requires approved revision')
    if piece.get('edited_after_approval') and not allow_edited_by:
        raise ValueError('Explicit human acknowledgement required for edited approved revision')
    if piece['format']=='carousel' and not assets:
        raise ValueError('Carousel requires RenderQA assets')
    for a in assets:
        if a['qa_status']!='pass' or a['content_revision']!=piece['revision'] or a['content_id']!=piece['id']:
            raise ValueError('Asset QA/revision mismatch')
        if piece.get('current_content_hash') and a.get('qa_report',{}).get('content_hash')!=piece['current_content_hash']:
            raise ValueError('Content changed since RenderQA')
        if digest(a['storage_uri'])!=a['sha256']:
            raise ValueError('Asset changed after QA')
    dest=Path(out_root)/piece['id']/('r'+str(piece['revision']))
    dest.mkdir(parents=True, exist_ok=True)
    manifest={'content_id':piece['id'], 'revision':piece['revision'], 'content_hash':piece.get('current_content_hash'), 'post_text':piece['body'],
              'first_comment':(piece.get('payload') or {}).get('first_comment',''),
              'alt_text': [alt for asset in assets for alt in (asset.get('qa_report') or {}).get('alt_text',[])],
              'carousel_pdf_path':None, 'files':{}, 'edited_acknowledged_by':allow_edited_by}
    (dest/'post.txt').write_text(piece['body'],encoding='utf-8')
    (dest/'first_comment.txt').write_text(manifest['first_comment'],encoding='utf-8')
    (dest/'alt_text.json').write_text(json.dumps(manifest['alt_text'],ensure_ascii=False),encoding='utf-8')
    for i,a in enumerate(assets):
        target=dest/('asset_'+str(i)+Path(a['storage_uri']).suffix)
        shutil.copyfile(a['storage_uri'], target)
        if a['kind']=='pdf':manifest['carousel_pdf_path']=str(target.resolve())
    manifest['files']={p.name:digest(p) for p in dest.iterdir() if p.is_file() and p.name!='package.json'}
    manifest['checksum']=hashlib.sha256(json.dumps(manifest,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
    (dest/'package.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    return manifest


def linkedin_xlsx(path):
    from openpyxl import load_workbook
    book=load_workbook(path,read_only=True,data_only=True)
    allowed={'Impressions':'impressions','Reactions':'reactions','Comments':'comments',
             'Reposts':'shares','Saves':'saves','Profile viewers from this post':'profile_visits','Link engagements':'clicks'}
    values={}
    urls=set()
    for sheet in book:
        for row in sheet.values:
            if len(row)<2:continue
            if row[0]=='Post URL':urls.add(str(row[1]).strip())
            if row[0] in allowed and row[1] is not None:
                value=float(str(row[1]).replace(',',''))
                if value<0 or not value.is_integer():raise ValueError('Non-integer/negative metric')
                key=allowed[row[0]]
                if key in values:raise ValueError('Ambiguous duplicate metric: '+key)
                values[key]=int(value)
    book.close()
    if len(urls)!=1 or not values:raise ValueError('Expected one identifiable post export')
    return {'url':urls.pop(),'metrics':values}


def past_posts(path, language=None):
    path=Path(path)
    rows=json.loads(path.read_text()) if path.suffix=='.json' else [{'body':path.read_text(),'language':language}]
    if isinstance(rows,dict):rows=[rows]
    for r in rows:
        if r.get('is_exemplar') or r.get('is_anti_example'):raise ValueError('Exemplar flags are human-only')
        if r.get('language') not in ('he','en') or not r.get('body','').strip():raise ValueError('body/language required')
    return [{'body':r['body'],'language':r['language'],'url':r.get('url'),'external_post_id':r.get('external_post_id'),
             'format':r.get('format','text_post'),'channel':'linkedin','notes':'Imported draft; human review pending'} for r in rows]

if __name__=='__main__':
    import sys
    a=json.load(sys.stdin)
    op=a.pop('op')
    print(json.dumps(globals()[op](**a),ensure_ascii=False))
