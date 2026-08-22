#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,time
from datetime import date,datetime,timedelta,timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request,urlopen
API="https://api.finmindtrade.com/api/v4/data"
DATASET="TaiwanStockInstitutionalInvestorsBuySell"
class FinMindError(RuntimeError):pass
def integer(v:Any)->int:
 try:return int(v)
 except (TypeError,ValueError) as exc:raise FinMindError(f"invalid integer: {v!r}") from exc
def normalize(payload:Any,code:str,end_date:str,days:int)->list[dict[str,Any]]:
 if not isinstance(payload,dict) or payload.get("status")!=200 or not isinstance(payload.get("data"),list):raise FinMindError(f"FinMind schema/status error for {code}")
 by={};seen=set()
 for row in payload["data"]:
  if not isinstance(row,dict) or row.get("stock_id")!=code:raise FinMindError(f"identity mismatch for {code}")
  day=str(row.get("date") or "");name=row.get("name")
  if day>end_date or name not in {"Foreign_Investor","Investment_Trust"}:continue
  key=(day,name)
  if key in seen:raise FinMindError(f"duplicate category: {key}")
  seen.add(key);item=by.setdefault(day,{"trade_date":day,"foreign_net_shares":None,"sitc_net_shares":None,"missing":False,"source_url":API,"source_tier":"third_party_fallback"});net=integer(row.get("buy"))-integer(row.get("sell"))
  if name=="Foreign_Investor":item["foreign_net_shares"]=net
  else:item["sitc_net_shares"]=net
 history=sorted(by.values(),key=lambda x:x["trade_date"])[-days:]
 for item in history:item["missing"]=item["foreign_net_shares"] is None or item["sitc_net_shares"] is None
 return history
def fetch(code:str,start:str,end:str,timeout:float=30)->Any:
 q=urlencode({"dataset":DATASET,"data_id":code,"start_date":start,"end_date":end});req=Request(API+"?"+q,headers={"User-Agent":"tw-stock-momentum-report/1.0","Accept":"application/json"})
 with urlopen(req,timeout=timeout) as res:return json.loads(res.read().decode("utf-8-sig"))
def collect(targets_path:Path,end_date:str,days:int,calendar_lookback:int=40)->dict[str,Any]:
 if days<3:raise FinMindError("days must be at least 3")
 doc=json.loads(targets_path.read_text(encoding="utf-8"));targets=doc.get("targets")
 if not isinstance(targets,list) or not targets:raise FinMindError("targets missing")
 if doc.get("trade_date") and doc["trade_date"]!=end_date:raise FinMindError("target date mismatch")
 end=date.fromisoformat(end_date);start=(end-timedelta(days=calendar_lookback)).isoformat();records=[];warnings=[]
 for target in targets:
  code=target.get("stock_code");history=normalize(fetch(code,start,end_date),code,end_date,days)
  if len(history)<days:warnings.append(f"{code} only {len(history)} trading days")
  if any(x["missing"] for x in history):warnings.append(f"{code} contains missing institutional categories")
  records.append({"market":target.get("market"),"stock_code":code,"stock_name":target.get("stock_name"),"trade_date":end_date,"history_count":len(history),"sitc_history":history});time.sleep(0.4)
 return {"schema_version":"1.0","trade_date":end_date,"requested_trading_days":days,"source":"FinMind TaiwanStockInstitutionalInvestorsBuySell","source_url":API,"source_tier":"third_party_fallback","confidence":"medium_pending_official_reconciliation","generated_at":datetime.now(timezone.utc).isoformat(),"warnings":warnings+["官方恢復後須逐日核對；不得視為官方原始檔"],"records":records}
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--targets",type=Path,required=True);p.add_argument("--end-date",required=True);p.add_argument("--days",type=int,default=10);p.add_argument("--output",type=Path,required=True);a=p.parse_args();result=collect(a.targets,a.end_date,a.days);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8");print(f"wrote {len(result.get("records",[]))} FinMind fallback histories");return 0
if __name__=="__main__":
 try:raise SystemExit(main())
 except FinMindError as exc:print(f"ERROR: {exc}",file=__import__("sys").stderr);raise SystemExit(2)
