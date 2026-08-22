#!/usr/bin/env python3
"""Backfill official institutional history only for preselected targets."""
from __future__ import annotations
import argparse,json,time
from dataclasses import asdict
from datetime import date,datetime,timedelta,timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request,urlopen
from urllib.error import HTTPError,URLError
from fetch_official_data import DataError,InstitutionalRecord,parse_integer,parse_twse
TWSE='https://www.twse.com.tw/rwd/zh/fund/T86?response=json&date={date}&selectType=ALLBUT0999'
TPEX='https://www.tpex.org.tw/www/zh-tw/insti/dailyTrade?{query}'
class HistoryError(RuntimeError):pass

def roc_slash_to_iso(value:Any)->str:
 text=str(value).strip();parts=text.split('/')
 if len(parts)!=3:raise HistoryError(f'invalid ROC slash date: {value!r}')
 try:return date(int(parts[0])+1911,int(parts[1]),int(parts[2])).isoformat()
 except ValueError as exc:raise HistoryError(f'invalid ROC slash date: {value!r}') from exc

def parse_tpex_history(payload:Any,url:str,stamp:str)->list[InstitutionalRecord]:
 if not isinstance(payload,dict) or not isinstance(payload.get('tables'),list) or not payload['tables']:
  raise HistoryError('TPEx historical institutional schema missing')
 table=payload['tables'][0];rows=table.get('data');trade_date=roc_slash_to_iso(table.get('date'))
 if not isinstance(rows,list):raise HistoryError('TPEx historical data must be an array')
 result=[];seen=set()
 for row in rows:
  if not isinstance(row,list) or len(row)<24:raise HistoryError('TPEx historical row too short')
  code=str(row[0]).strip();key=(trade_date,'TPEx',code)
  if key in seen:raise HistoryError(f'duplicate TPEx historical key: {key}')
  seen.add(key)
  result.append(InstitutionalRecord(trade_date,code,str(row[1]).strip(),'TPEx',parse_integer(row[4]),parse_integer(row[13]),'TPEx historical institutional detail',url,stamp))
 return result

def fetch_json(url:str,timeout:float=20,attempts:int=3)->tuple[Any,str]:
 error=None
 for n in range(attempts):
  try:
   request=Request(url,headers={'User-Agent':'tw-stock-momentum-report/1.0','Accept':'application/json'})
   with urlopen(request,timeout=timeout) as response:raw=response.read();stamp=datetime.now(timezone.utc).isoformat()
   return json.loads(raw.decode('utf-8-sig')),stamp
  except (HTTPError,URLError,TimeoutError,json.JSONDecodeError,UnicodeDecodeError) as exc:
   error=exc
   if n+1<attempts:time.sleep(2**n)
 raise HistoryError(f'history fetch failed: {error}')

def fetch_day(market:str,day:date)->list[InstitutionalRecord]|None:
 if market=='TWSE':
  url=TWSE.format(date=day.strftime('%Y%m%d'));payload,stamp=fetch_json(url)
  if not isinstance(payload,dict) or payload.get('stat')!='OK':return None
  try:return parse_twse(payload,url,stamp)
  except DataError as exc:raise HistoryError(str(exc)) from exc
 query=urlencode({'type':'Daily','sect':'EW','date':day.isoformat().replace('-','/')})
 url=TPEX.format(query=query);payload,stamp=fetch_json(url)
 if not isinstance(payload,dict) or not payload.get('tables'):return None
 return parse_tpex_history(payload,url,stamp)

def cache_file(cache_dir:Path,market:str,day:date)->Path:
 return cache_dir/market.lower()/f'{day:%Y%m%d}.json'

def cached_day(market:str,day:date,cache_dir:Path|None=None,failure_cooldown_seconds:int=900)->list[InstitutionalRecord]|None:
 if cache_dir is None:return fetch_day(market,day)
 path=cache_file(cache_dir,market,day);error_path=path.with_suffix('.error.json')
 if path.exists():
  try:
   doc=json.loads(path.read_text(encoding='utf-8'))
   if doc.get('market')!=market or doc.get('trade_date')!=day.isoformat():raise ValueError('cache metadata mismatch')
   if doc.get('status')=='no_data':return None
   rows=doc.get('records')
   if not isinstance(rows,list):raise ValueError('records missing')
   return [InstitutionalRecord(**row) for row in rows]
  except (OSError,json.JSONDecodeError,ValueError,TypeError) as exc:raise HistoryError(f'invalid institutional cache {path}: {exc}') from exc
 if error_path.exists():
  try:
   err=json.loads(error_path.read_text(encoding='utf-8'));failed=datetime.fromisoformat(err['failed_at']);age=(datetime.now(timezone.utc)-failed).total_seconds()
   if age<failure_cooldown_seconds:raise HistoryError(f'cached official failure ({int(age)}s old): {err.get("reason")}')
  except HistoryError:raise
  except (OSError,json.JSONDecodeError,KeyError,ValueError):pass
 try:records=fetch_day(market,day)
 except HistoryError as exc:
  error_path.parent.mkdir(parents=True,exist_ok=True);tmp=error_path.with_suffix('.tmp');tmp.write_text(json.dumps({'market':market,'trade_date':day.isoformat(),'failed_at':datetime.now(timezone.utc).isoformat(),'reason':str(exc)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');tmp.replace(error_path);raise
 path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_suffix('.tmp');tmp.write_text(json.dumps({'schema_version':'1.0','market':market,'trade_date':day.isoformat(),'status':'ok' if records is not None else 'no_data','records':[] if records is None else [asdict(r) for r in records]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');tmp.replace(path)
 if error_path.exists():error_path.unlink()
 return records

def load_targets(path:Path)->tuple[str,dict[str,set[str]],dict[tuple[str,str],str]]:
 try:doc=json.loads(path.read_text(encoding='utf-8'))
 except (OSError,json.JSONDecodeError) as exc:raise HistoryError(f'cannot load targets: {exc}') from exc
 if not isinstance(doc.get('targets'),list) or not doc['targets']:raise HistoryError('targets array is empty or missing')
 markets={'TWSE':set(),'TPEx':set()};names={}
 for row in doc['targets']:
  market=row.get('market');code=row.get('stock_code')
  if market not in markets or not isinstance(code,str) or not code:raise HistoryError('invalid target identity')
  if code in markets[market]:raise HistoryError(f'duplicate target: {(market,code)}')
  markets[market].add(code);names[(market,code)]=row.get('stock_name')
 return str(doc.get('trade_date') or ''),{m:v for m,v in markets.items() if v},names

def collect(targets_path:Path,end_date:str,days:int,max_calendar_days:int=40,cache_dir:Path|None=None,failure_cooldown_seconds:int=900)->dict[str,Any]:
 if days<3:raise HistoryError('days must be at least 3')
 target_date,markets,names=load_targets(targets_path)
 if target_date and target_date!=end_date:raise HistoryError(f'target date {target_date} differs from end date {end_date}')
 try:cursor=date.fromisoformat(end_date)
 except ValueError as exc:raise HistoryError('end date must be YYYY-MM-DD') from exc
 histories={(m,c):[] for m,codes in markets.items() for c in codes};successful={m:0 for m in markets};warnings=[]
 checked=0
 while checked<max_calendar_days and any(n<days for n in successful.values()):
  if cursor.weekday()<5:
   for market in markets:
    if successful[market]>=days:continue
    records=cached_day(market,cursor,cache_dir,failure_cooldown_seconds)
    if records is None:continue
    successful[market]+=1;lookup={r.stock_code:r for r in records}
    for code in markets[market]:
     r=lookup.get(code)
     if r is None:
      histories[(market,code)].append({'trade_date':cursor.isoformat(),'foreign_net_shares':None,'sitc_net_shares':None,'missing':True})
      warnings.append(f'{market} {code} missing from official table on {cursor.isoformat()}')
     else:histories[(market,code)].append({'trade_date':r.trade_date,'foreign_net_shares':r.foreign_net_shares,'sitc_net_shares':r.sitc_net_shares,'missing':False,'source_url':r.source_url})
  cursor-=timedelta(days=1);checked+=1
 if any(n<days for n in successful.values()):raise HistoryError(f'insufficient official trading days: {successful}, requested {days}')
 records=[]
 for key,history in sorted(histories.items()):
  history.sort(key=lambda r:r['trade_date'])
  records.append({'market':key[0],'stock_code':key[1],'stock_name':names[key],'trade_date':end_date,'sitc_history':history,'history_count':len(history)})
 return {'schema_version':'1.0','trade_date':end_date,'requested_trading_days':days,'successful_market_days':successful,'warnings':warnings,'records':records}

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--targets',type=Path,required=True);p.add_argument('--end-date',required=True);p.add_argument('--days',type=int,default=10);p.add_argument('--output',type=Path,required=True);p.add_argument('--cache-dir',type=Path);p.add_argument('--failure-cooldown-seconds',type=int,default=900);a=p.parse_args()
 result=collect(a.targets,a.end_date,a.days,cache_dir=a.cache_dir,failure_cooldown_seconds=a.failure_cooldown_seconds);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(f"wrote {len(result['records'])} target histories; market days {result['successful_market_days']}")
 return 0
if __name__=='__main__':
 try:raise SystemExit(main())
 except HistoryError as exc:print(f'ERROR: {exc}',file=__import__('sys').stderr);raise SystemExit(2)
