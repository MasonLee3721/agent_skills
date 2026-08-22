#!/usr/bin/env python3
"""Create the only allowed target list for expensive historical fetches."""
from __future__ import annotations
import argparse,json
from pathlib import Path
from typing import Any

class TargetError(RuntimeError): pass

def select_targets(dataset: dict[str,Any], institutional_days: int=10, price_days: int=120) -> dict[str,Any]:
    if institutional_days<3 or price_days<60: raise TargetError('history windows below report minimum')
    records=dataset.get('records')
    if not isinstance(records,list): raise TargetError('dataset.records must be an array')
    targets=[]; seen=set()
    for row in records:
        if not isinstance(row,dict): raise TargetError('dataset row must be an object')
        pre=row.get('preselection')
        if not isinstance(pre,dict) or not isinstance(pre.get('passed'),bool): raise TargetError('preselection result missing')
        if not pre['passed']: continue
        market=row.get('market'); code=row.get('stock_code')
        if market not in {'TWSE','TPEx'} or not isinstance(code,str) or not code: raise TargetError('invalid target identity')
        key=(market,code)
        if key in seen: raise TargetError(f'duplicate target: {key}')
        seen.add(key)
        targets.append({'market':market,'stock_code':code,'stock_name':row.get('stock_name'),
                        'institutional_history_days':institutional_days,'price_history_days':price_days})
    targets.sort(key=lambda r:(r['market'],r['stock_code']))
    return {'schema_version':'1.0','trade_date':dataset.get('trade_date'),
            'source_analyzable_count':len(records),'target_count':len(targets),'targets':targets}

def main()->int:
    p=argparse.ArgumentParser(); p.add_argument('--dataset',type=Path,required=True); p.add_argument('--output',type=Path,required=True)
    p.add_argument('--institutional-days',type=int,default=10); p.add_argument('--price-days',type=int,default=120); a=p.parse_args()
    try: dataset=json.loads(a.dataset.read_text(encoding='utf-8'))
    except (OSError,json.JSONDecodeError) as exc: raise TargetError(f'cannot load dataset: {exc}') from exc
    result=select_targets(dataset,a.institutional_days,a.price_days)
    a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f"selected {result['target_count']} of {result['source_analyzable_count']} analyzable records")
    return 0
if __name__=='__main__':
    try: raise SystemExit(main())
    except TargetError as exc: print(f'ERROR: {exc}',file=__import__('sys').stderr); raise SystemExit(2)
