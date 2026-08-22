#!/usr/bin/env python3
"""Fetch official listed/OTC company capital and issued common-share data."""
from __future__ import annotations
import argparse,json,re,time
from http.client import IncompleteRead
from dataclasses import asdict,dataclass
from datetime import date,datetime,timezone
from decimal import Decimal,InvalidOperation
from pathlib import Path
from typing import Any
from urllib.error import HTTPError,URLError
from urllib.request import Request,urlopen

TWSE_URL='https://openapi.twse.com.tw/v1/opendata/t187ap03_L'
TPEX_URL='https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap03_O'
class CompanyDataError(RuntimeError): pass

@dataclass(frozen=True)
class CompanyRecord:
 market:str; stock_code:str; stock_name:str; security_type:str; data_date:str
 paid_in_capital_twd:int|None; issued_shares:int|None; par_value_twd:str|None
 issued_shares_is_estimated:bool; source_name:str; source_url:str; fetched_at:str

def roc_to_iso(value:Any)->str:
 text=str(value).strip()
 if len(text)!=7 or not text.isdigit(): raise CompanyDataError(f'invalid ROC date: {value!r}')
 try:return date(int(text[:3])+1911,int(text[3:5]),int(text[5:7])).isoformat()
 except ValueError as exc: raise CompanyDataError(f'invalid ROC date: {value!r}') from exc

def integer(value:Any)->int|None:
 if value is None:return None
 text=str(value).strip().replace(',','')
 if text in {'','--','---','N/A'}:return None
 try:return int(text)
 except ValueError as exc:raise CompanyDataError(f'invalid integer: {value!r}') from exc

def par_value(value:Any)->str|None:
 if value is None:return None
 text=str(value).strip()
 if not text:return None
 match=re.search(r'([0-9]+(?:\.[0-9]+)?)\s*元',text)
 if not match:return None
 try:value=Decimal(match.group(1))
 except InvalidOperation:return None
 if value<=0:return None
 return format(value,'f')

def _unique(records:list[CompanyRecord])->list[CompanyRecord]:
 seen=set()
 for r in records:
  key=(r.market,r.stock_code)
  if key in seen:raise CompanyDataError(f'duplicate company key: {key}')
  seen.add(key)
 return records

def parse_twse(payload:Any,url:str,fetched_at:str)->list[CompanyRecord]:
 if not isinstance(payload,list):raise CompanyDataError('TWSE company response must be an array')
 result=[]
 for row in payload:
  if not isinstance(row,dict):raise CompanyDataError('TWSE company row must be an object')
  code=str(row.get('公司代號','')).strip()
  if not code:raise CompanyDataError('TWSE company code missing')
  result.append(CompanyRecord('TWSE',code,str(row.get('公司簡稱') or row.get('公司名稱') or '').strip(),'common_stock',roc_to_iso(row.get('出表日期')),
    integer(row.get('實收資本額')),integer(row.get('已發行普通股數或TDR原股發行股數')),par_value(row.get('普通股每股面額')),False,'TWSE listed company profile',url,fetched_at))
 return _unique(result)

def parse_tpex(payload:Any,url:str,fetched_at:str)->list[CompanyRecord]:
 if not isinstance(payload,list):raise CompanyDataError('TPEx company response must be an array')
 result=[]
 for row in payload:
  if not isinstance(row,dict):raise CompanyDataError('TPEx company row must be an object')
  code=str(row.get('SecuritiesCompanyCode','')).strip()
  if not code:raise CompanyDataError('TPEx company code missing')
  result.append(CompanyRecord('TPEx',code,str(row.get('CompanyAbbreviation') or row.get('CompanyName') or '').strip(),'common_stock',roc_to_iso(row.get('Date')),
    integer(row.get('Paidin.Capital.NTDollars')),integer(row.get('IssueShares')),par_value(row.get('ParValueOfCommonStock')),False,'TPEx OTC company profile',url,fetched_at))
 return _unique(result)

def fetch_json(url:str,timeout:float=20,attempts:int=3)->tuple[Any,str]:
 error=None
 for attempt in range(attempts):
  try:
   req=Request(url,headers={'User-Agent':'tw-stock-momentum-report/1.0','Accept':'application/json'})
   with urlopen(req,timeout=timeout) as response:raw=response.read();stamp=datetime.now(timezone.utc).isoformat()
   return json.loads(raw.decode('utf-8-sig')),stamp
  except (HTTPError,URLError,TimeoutError,IncompleteRead,json.JSONDecodeError,UnicodeDecodeError) as exc:
   error=exc
   if attempt+1<attempts:time.sleep(2**attempt)
 raise CompanyDataError(f'official company fetch failed: {error}')

def fetch_market(market:str)->list[CompanyRecord]:
 url=TWSE_URL if market=='twse' else TPEX_URL
 payload,stamp=fetch_json(url)
 return parse_twse(payload,url,stamp) if market=='twse' else parse_tpex(payload,url,stamp)

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--market',choices=('twse','tpex','all'),default='all');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 markets=('twse','tpex') if a.market=='all' else (a.market,);records=[]
 for market in markets:records.extend(fetch_market(market))
 _unique(records)
 dates={m:sorted({r.data_date for r in records if r.market==m}) for m in ('TWSE','TPEx') if any(r.market==m for r in records)}
 invalid=[r.stock_code for r in records if r.issued_shares is None or r.issued_shares<=0 or r.paid_in_capital_twd is None]
 doc={'schema_version':'1.0','generated_at':datetime.now(timezone.utc).isoformat(),'data_dates':dates,
      'counts':{'records':len(records),'invalid_capital_or_shares':len(invalid)},'records':[asdict(r) for r in records]}
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(f'wrote {len(records)} companies; {len(invalid)} missing/invalid capital or issued shares')
 return 0
if __name__=='__main__':
 try:raise SystemExit(main())
 except CompanyDataError as exc:print(f'ERROR: {exc}',file=__import__('sys').stderr);raise SystemExit(2)
