#!/usr/bin/env python3
"""Fetch 60-120 official OHLCV trading days only for preselected targets."""
from __future__ import annotations
import argparse,json,time
from datetime import date,datetime,timedelta,timezone
from decimal import Decimal,InvalidOperation
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request,urlopen
from urllib.error import HTTPError,URLError
from http.client import IncompleteRead
TWSE='https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?response=json&date={month}&stockNo={code}'
TPEX='https://www.tpex.org.tw/www/zh-tw/afterTrading/tradingStock?{query}'
class PriceHistoryError(RuntimeError):pass

def roc_slash_to_iso(value:Any)->str:
 parts=str(value).strip().split('/')
 if len(parts)!=3:raise PriceHistoryError(f'invalid ROC date: {value!r}')
 try:return date(int(parts[0])+1911,int(parts[1]),int(parts[2])).isoformat()
 except ValueError as exc:raise PriceHistoryError(f'invalid ROC date: {value!r}') from exc

def integer(value:Any)->int:
 try:return int(str(value).strip().replace(',',''))
 except ValueError as exc:raise PriceHistoryError(f'invalid integer: {value!r}') from exc

def decimal_text(value:Any)->str:
 text=str(value).strip().replace(',','')
 if text.startswith('X'):text=text[1:]
 try:return format(Decimal(text),'f')
 except InvalidOperation as exc:raise PriceHistoryError(f'invalid price: {value!r}') from exc

def parse_twse_month(payload:Any)->list[dict[str,Any]]:
 if not isinstance(payload,dict) or payload.get('stat')!='OK':return []
 fields=payload.get('fields');rows=payload.get('data')
 required=['日期','成交股數','開盤價','最高價','最低價','收盤價','漲跌價差']
 if not isinstance(fields,list) or not isinstance(rows,list) or any(x not in fields for x in required):raise PriceHistoryError('TWSE monthly schema missing')
 idx={x:fields.index(x) for x in required};result=[]
 for row in rows:
  if not isinstance(row,list) or len(row)<len(fields):raise PriceHistoryError('TWSE monthly row too short')
  result.append({'trade_date':roc_slash_to_iso(row[idx['日期']]),'open':decimal_text(row[idx['開盤價']]),'high':decimal_text(row[idx['最高價']]),'low':decimal_text(row[idx['最低價']]),'close':decimal_text(row[idx['收盤價']]),'change':decimal_text(row[idx['漲跌價差']]),'volume_shares':integer(row[idx['成交股數']])})
 return result

def parse_tpex_month(payload:Any)->list[dict[str,Any]]:
 if not isinstance(payload,dict) or not isinstance(payload.get('tables'),list) or not payload['tables']:return []
 rows=payload['tables'][0].get('data')
 if not isinstance(rows,list):raise PriceHistoryError('TPEx monthly data missing')
 result=[]
 for row in rows:
  if not isinstance(row,list) or len(row)<9:raise PriceHistoryError('TPEx monthly row too short')
  result.append({'trade_date':roc_slash_to_iso(row[0]),'open':decimal_text(row[3]),'high':decimal_text(row[4]),'low':decimal_text(row[5]),'close':decimal_text(row[6]),'change':decimal_text(row[7]),'volume_shares':integer(row[1])*1000})
 return result

def fetch_json(url:str,timeout:float=20,attempts:int=4)->Any:
 error=None
 for n in range(attempts):
  try:
   req=Request(url,headers={'User-Agent':'tw-stock-momentum-report/1.0','Accept':'application/json'})
   with urlopen(req,timeout=timeout) as response:raw=response.read()
   return json.loads(raw.decode('utf-8-sig'))
  except (HTTPError,URLError,TimeoutError,IncompleteRead,json.JSONDecodeError,UnicodeDecodeError) as exc:
   error=exc
   if n+1<attempts:time.sleep(10*(n+1) if isinstance(exc,HTTPError) and exc.code==307 else 2**n)
 raise PriceHistoryError(f'price history fetch failed for {url}: {error}')

def previous_month(day:date)->date:
 return date(day.year-1,12,1) if day.month==1 else date(day.year,day.month-1,1)

def fetch_month(market:str,code:str,month:date)->list[dict[str,Any]]:
 if market=='TWSE':
  url=TWSE.format(month=month.strftime('%Y%m01'),code=code);return parse_twse_month(fetch_json(url))
 query=urlencode({'code':code,'date':month.strftime('%Y/%m/01')});url=TPEX.format(query=query);return parse_tpex_month(fetch_json(url))

def cache_path(cache_dir:Path,market:str,code:str,month:date)->Path:
 safe_market='twse' if market=='TWSE' else 'tpex'
 return cache_dir/safe_market/code/f'{month:%Y%m}.json'

def cached_month(market:str,code:str,month:date,cache_dir:Path|None=None,refresh:bool=False)->list[dict[str,Any]]:
 path=cache_path(cache_dir,market,code,month) if cache_dir else None
 if path and path.exists() and not refresh:
  try:
   doc=json.loads(path.read_text(encoding='utf-8'));rows=doc.get('rows')
   if doc.get('market')!=market or doc.get('stock_code')!=code or doc.get('month')!=month.strftime('%Y-%m') or not isinstance(rows,list):raise ValueError('cache metadata mismatch')
   return rows
  except (OSError,json.JSONDecodeError,ValueError) as exc:raise PriceHistoryError(f'invalid price cache {path}: {exc}') from exc
 rows=fetch_month(market,code,month)
 if path:
  path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_suffix('.tmp')
  tmp.write_text(json.dumps({'schema_version':'1.0','market':market,'stock_code':code,'month':month.strftime('%Y-%m'),'fetched_at':datetime.now(timezone.utc).isoformat(),'rows':rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');tmp.replace(path)
 return rows

def load_targets(path:Path)->tuple[str,list[dict[str,Any]]]:
 try:doc=json.loads(path.read_text(encoding='utf-8'))
 except (OSError,json.JSONDecodeError) as exc:raise PriceHistoryError(f'cannot load targets: {exc}') from exc
 rows=doc.get('targets')
 if not isinstance(rows,list) or not rows:raise PriceHistoryError('targets missing')
 seen=set()
 for r in rows:
  key=(r.get('market'),r.get('stock_code'))
  if key[0] not in {'TWSE','TPEx'} or not isinstance(key[1],str) or not key[1]:raise PriceHistoryError('invalid target')
  if key in seen:raise PriceHistoryError(f'duplicate target: {key}')
  seen.add(key)
 return str(doc.get('trade_date') or ''),rows


def is_single_weekday_gap(previous:str,end_date:str)->bool:
 try:start=date.fromisoformat(previous);end=date.fromisoformat(end_date)
 except ValueError:return False
 if start>=end:return False
 return sum(1 for n in range(1,(end-start).days+1) if (start+timedelta(days=n)).weekday()<5)==1

def load_daily_quotes(path:Path,end_date:str)->dict[tuple[str,str],dict[str,Any]]:
 try:doc=json.loads(path.read_text(encoding='utf-8'))
 except (OSError,json.JSONDecodeError) as exc:raise PriceHistoryError(f'cannot load daily quotes: {exc}') from exc
 if doc.get('trade_date')!=end_date:raise PriceHistoryError('daily quote date mismatch')
 out={}
 for row in doc.get('records') or []:
  key=(row.get('market'),row.get('stock_code'))
  if row.get('trade_date')!=end_date or key in out:raise PriceHistoryError(f'invalid daily quote key: {key}')
  values={k:row.get(k) for k in ('open','high','low','close','change','volume_shares')}
  if all(values[k] is not None for k in ('open','high','low','close','volume_shares')):out[key]={'trade_date':end_date,**values,'source_name':row.get('source_name'),'data_status':'actual_fallback'}
 return out

def collect(targets_path:Path,end_date:str,days:int,max_months:int=12,cache_dir:Path|None=None,refresh_cache:bool=False,daily_quotes_path:Path|None=None)->dict[str,Any]:
 if days<60 or days>240:raise PriceHistoryError('days must be between 60 and 240')
 target_date,targets=load_targets(targets_path)
 if target_date and target_date!=end_date:raise PriceHistoryError(f'target date {target_date} differs from {end_date}')
 try:end=date.fromisoformat(end_date)
 except ValueError as exc:raise PriceHistoryError('end date must be YYYY-MM-DD') from exc
 quote_map=load_daily_quotes(daily_quotes_path,end_date) if daily_quotes_path else {}
 outputs=[];warnings=[];failures=[]
 for target in targets:
  market=target['market'];code=target['stock_code'];month=date(end.year,end.month,1);by_date={}
  try:
   for _ in range(max_months):
    for row in cached_month(market,code,month,cache_dir,refresh_cache):
     if row['trade_date']<=end_date:by_date[row['trade_date']]=row
    if len(by_date)>=days:break
    month=previous_month(month);time.sleep(0.6)
   history=sorted(by_date.values(),key=lambda r:r['trade_date'])[-days:]
   if len(history)<days:raise PriceHistoryError(f'{market} {code} has only {len(history)} trading days, requested {days}')
   fallback_applied=False
   if history[-1]['trade_date']!=end_date:
    quote=quote_map.get((market,code))
    if quote and is_single_weekday_gap(history[-1]['trade_date'],end_date):
     history=(history+[quote])[-days:];fallback_applied=True;warnings.append(f'{market} {code}: appended verified daily quote for {end_date}')
    else:raise PriceHistoryError(f"{market} {code} latest price {history[-1]['trade_date']}, expected {end_date}")
   if len(history)<days:raise PriceHistoryError(f'{market} {code} has only {len(history)} trading days after fallback, requested {days}')
   outputs.append({'market':market,'stock_code':code,'stock_name':target.get('stock_name'),'trade_date':end_date,'history_count':len(history),'ohlcv_history':history,'daily_fallback_applied':fallback_applied,'data_status':'actual_fallback' if fallback_applied else 'actual'})
  except PriceHistoryError as exc:
   message=str(exc);warnings.append(f'{market} {code}: {message}');failures.append({'market':market,'stock_code':code,'stock_name':target.get('stock_name'),'reason':message})
 return {'schema_version':'1.1','trade_date':end_date,'requested_trading_days':days,'generated_at':datetime.now(timezone.utc).isoformat(),'requested_count':len(targets),'completed_count':len(outputs),'failed_count':len(failures),'warnings':warnings,'failures':failures,'records':outputs}

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--targets',type=Path,required=True);p.add_argument('--end-date',required=True);p.add_argument('--days',type=int,default=120);p.add_argument('--output',type=Path,required=True);p.add_argument('--cache-dir',type=Path);p.add_argument('--refresh-cache',action='store_true');p.add_argument('--daily-quotes',type=Path);a=p.parse_args()
 result=collect(a.targets,a.end_date,a.days,cache_dir=a.cache_dir,refresh_cache=a.refresh_cache,daily_quotes_path=a.daily_quotes);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(f"wrote {len(result['records'])} target price histories of {a.days} days");return 0
if __name__=='__main__':
 try:raise SystemExit(main())
 except PriceHistoryError as exc:print(f'ERROR: {exc}',file=__import__('sys').stderr);raise SystemExit(2)
