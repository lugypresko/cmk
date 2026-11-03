"""JSON bridge: contracts from contracts.md and Guardian with DB-supplied context."""
import json
import re
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
from guardian import spec_gate, fact_gate, editorial_guardian
from guardian.report import assemble


def validate(contract, row):
    schemas=[]
    for block in re.findall(r'```json\n(.*?)```',Path('contracts.md').read_text(),re.S):
        if '"$id": "'+contract+'"' in block:
            schemas.append(json.loads(block))
    schema=next(s for s in schemas if s.get('$id')==contract)
    # Wrappers create drafts; the embedded report is attached only by Guardian afterwards.
    Draft202012Validator(schema,format_checker=FormatChecker()).validate(row)
    return row


def guardian(piece, ctx, facts, media_qa=None):
    ctx['checks']={c['id']:c for c in ctx['checklist']['checks']}
    p=dict(piece)
    if 'primary_language' in p:
        p.update(contract='cmk/CoreAsset',language=p['primary_language'],body=p.get('body_'+p['primary_language']),
                 thesis=p.get('thesis_'+p['primary_language']),cta=p.get('cta_'+p['primary_language']))
    else:p['contract']='cmk/ContentPiece'
    spec=spec_gate.check(p,ctx,strict=True,media_qa=media_qa)
    fact=fact_gate.check(p,facts)
    editorial=editorial_guardian.score(p,ctx,spec,fact)
    editorial['scorer']='heuristic-stub-v0'
    return assemble(p,spec,fact,editorial,ctx)

if __name__=='__main__':
    a=json.load(sys.stdin);op=a.pop('op')
    if op=='validate':result=validate(**a)
    elif op=='guardian':result=guardian(**a)
    elif op=='load_piece':
        from guardian.loader import load_piece
        result=load_piece(**a)
    else:raise ValueError('unknown bridge operation')
    print(json.dumps(result,ensure_ascii=False,default=str))
