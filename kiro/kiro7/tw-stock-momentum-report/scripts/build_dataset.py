#!/usr/bin/env python3
"""Join normalized institutional, company and daily quote documents.

This script performs no network access. It fails closed on date/schema errors and
keeps excluded securities with explicit reasons for auditability.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any

from momentum_core import Mode, ScreeningInput, investment_ratio_pct, preselect_candidate, screen_candidate


class DatasetError(RuntimeError):
    pass


def load_document(path: Path) -> dict[str, Any]:
    try:
        value=json.loads(path.read_text(encoding='utf-8'))
    except (OSError,json.JSONDecodeError) as exc:
        raise DatasetError(f"cannot load {path}: {exc}") from exc
    if not isinstance(value,dict): raise DatasetError(f"{path} must contain a JSON object")
    return value


def _key(row: dict[str,Any]) -> tuple[str,str]:
    market=str(row.get('market','')).strip()
    code=str(row.get('stock_code','')).strip()
    if market not in {'TWSE','TPEx'} or not code:
        raise DatasetError(f"invalid market/stock_code: {market!r}/{code!r}")
    return market,code


def index_unique(rows: Any, label: str) -> dict[tuple[str,str],dict[str,Any]]:
    if not isinstance(rows,list): raise DatasetError(f"{label}.records must be an array")
    result={}
    for row in rows:
        if not isinstance(row,dict): raise DatasetError(f"{label} row must be an object")
        key=_key(row)
        if key in result: raise DatasetError(f"duplicate {label} key: {key}")
        result[key]=row
    return result


def required_int(row: dict[str,Any], field: str, *, positive: bool=False) -> int:
    value=row.get(field)
    if isinstance(value,bool) or not isinstance(value,int): raise DatasetError(f"{field} must be an integer")
    if positive and value<=0: raise DatasetError(f"{field} must be positive")
    return value


def validate_trade_dates(document: dict[str,Any], rows: dict[tuple[str,str],dict[str,Any]], requested: str, label: str) -> None:
    declared=document.get('trade_date') or document.get('requested_trade_date')
    if declared is not None and declared!=requested:
        raise DatasetError(f"{label} declares {declared}, expected {requested}")
    dates={row.get('trade_date') for row in rows.values()}
    if dates!={requested}: raise DatasetError(f"{label} row dates {sorted(map(str,dates))}, expected {requested}")


def consecutive_buy_days(history: Any, requested: str) -> int | None:
    if history is None: return None
    if not isinstance(history,list): raise DatasetError('sitc_history must be an array')
    values=[]
    for row in history:
        if not isinstance(row,dict) or not isinstance(row.get('trade_date'),str):
            raise DatasetError('invalid sitc_history row')
        value=row.get('sitc_net_shares')
        if value is not None and (isinstance(value,bool) or not isinstance(value,int)):
            raise DatasetError('sitc_history.sitc_net_shares must be integer or null')
        values.append((row['trade_date'],value))
    values.sort(key=lambda item:item[0])
    if not values or values[-1][0]!=requested: return None
    streak=0
    for _,value in reversed(values):
        if value is None or value<=0: break
        streak+=1
    return streak


def decimal_text(value: Decimal | None) -> str | None:
    return None if value is None else format(value,'f')


def build_dataset(institutional: dict[str,Any], companies: dict[str,Any], quotes: dict[str,Any], requested: str) -> dict[str,Any]:
    inst=index_unique(institutional.get('records'),'institutional')
    company=index_unique(companies.get('records'),'companies')
    quote=index_unique(quotes.get('records'),'quotes')
    validate_trade_dates(institutional,inst,requested,'institutional')
    validate_trade_dates(quotes,quote,requested,'quotes')
    fallback_company_date=companies.get('data_date')

    rows=[]; exclusions=[]
    for key,c in sorted(company.items()):
        market,code=key
        reasons=[]
        if c.get('security_type')!='common_stock': reasons.append('non_common_stock')
        i=inst.get(key); q=quote.get(key)
        if i is None: reasons.append('missing_institutional')
        if q is None: reasons.append('missing_quote')
        company_date=c.get('data_date') or fallback_company_date
        if not isinstance(company_date,str) or not company_date: reasons.append('missing_company_data_date')
        issued=c.get('issued_shares')
        capital=c.get('paid_in_capital_twd')
        if isinstance(issued,bool) or not isinstance(issued,int) or issued<=0: reasons.append('invalid_issued_shares')
        if isinstance(capital,bool) or not isinstance(capital,int) or capital<0: reasons.append('invalid_paid_in_capital')
        if q is not None and q.get('trading_status_ok') is not True: reasons.append('trading_status_not_ok')
        if q is not None and q.get('liquidity_status_ok') is not True: reasons.append('liquidity_status_not_ok')
        if reasons:
            exclusions.append({'market':market,'stock_code':code,'reasons':sorted(set(reasons))})
            continue
        sitc=i.get('sitc_net_shares'); foreign=i.get('foreign_net_shares')
        if sitc is not None and (isinstance(sitc,bool) or not isinstance(sitc,int)): raise DatasetError('sitc_net_shares must be integer or null')
        if foreign is not None and (isinstance(foreign,bool) or not isinstance(foreign,int)): raise DatasetError('foreign_net_shares must be integer or null')
        volume=required_int(q,'volume_shares')
        ratio=None if sitc is None else investment_ratio_pct(sitc,issued)
        rows.append({
          'market':market,'stock_code':code,'stock_name':c.get('stock_name') or i.get('stock_name') or q.get('stock_name'),
          'trade_date':requested,'company_data_date':company_date,
          'paid_in_capital_twd':capital,'issued_shares':issued,
          'issued_shares_is_estimated':bool(c.get('issued_shares_is_estimated',False)),
          'foreign_net_shares':foreign,'sitc_net_shares':sitc,
          'investment_ratio_pct':ratio,'volume_shares':volume,'volume_lots':Decimal(volume)/Decimal(1000),
          'consecutive_sitc_buy_days':consecutive_buy_days(i.get('sitc_history'),requested),
          'open':q.get('open'),'high':q.get('high'),'low':q.get('low'),'close':q.get('close'),
          'sources':{'institutional':i.get('source_url'),'company':c.get('source_url'),'quote':q.get('source_url')}
        })

    positive=sorted((r for r in rows if r['investment_ratio_pct'] is not None and r['investment_ratio_pct']>0),key=lambda r:(-r['investment_ratio_pct'],r['market'],r['stock_code']))
    ranks={(r['market'],r['stock_code']):n for n,r in enumerate(positive,1)}
    output=[]
    for row in rows:
        rank=ranks.get((row['market'],row['stock_code']))
        volume_lots=row['volume_lots']
        base=ScreeningInput(stock_code=row['stock_code'],investment_ratio_pct=row['investment_ratio_pct'],positive_ratio_rank=rank,
          volume_lots=volume_lots,paid_in_capital_twd=row['paid_in_capital_twd'],sitc_net_shares=row['sitc_net_shares'],
          consecutive_sitc_buy_days=row['consecutive_sitc_buy_days'],is_common_stock=True,trading_status_ok=True,liquidity_status_ok=True)
        row['positive_ratio_rank']=rank
        preselection=preselect_candidate(base)
        row['preselection']={'passed':preselection.passed,'checks':preselection.checks,'reasons':list(preselection.reasons)}
        row['history_required']=preselection.passed and row['consecutive_sitc_buy_days'] is None
        row['screening']={mode.value:{'passed':res.passed,'checks':res.checks,'reasons':list(res.reasons)} for mode in Mode for res in [screen_candidate(base,mode)]}
        for field in ('investment_ratio_pct','volume_lots'): row[field]=decimal_text(row[field])
        output.append(row)
    return {'schema_version':'1.0','trade_date':requested,'company_data_date':company_date,
      'generated_at':datetime.now(timezone.utc).isoformat(),
      'counts':{'company_universe':len(company),'analyzable':len(output),'excluded':len(exclusions),
                'preselected':sum(r['preselection']['passed'] for r in output),
                'history_required':sum(r['history_required'] for r in output),
                'aggressive_passed':sum(r['screening']['aggressive']['passed'] for r in output),
                'conservative_passed':sum(r['screening']['conservative']['passed'] for r in output)},
      'records':output,'exclusions':exclusions}


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument('--institutional',type=Path,required=True)
    parser.add_argument('--companies',type=Path,required=True)
    parser.add_argument('--quotes',type=Path,required=True)
    parser.add_argument('--date',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    result=build_dataset(load_document(args.institutional),load_document(args.companies),load_document(args.quotes),args.date)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f"wrote {result['counts']['analyzable']} rows; excluded {result['counts']['excluded']} to {args.output}")
    return 0


if __name__=='__main__':
    try: raise SystemExit(main())
    except DatasetError as exc:
        print(f"ERROR: {exc}",file=__import__('sys').stderr); raise SystemExit(2)
