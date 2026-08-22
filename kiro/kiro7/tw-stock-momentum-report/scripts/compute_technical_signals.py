#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from datetime import datetime,timezone
from decimal import Decimal
from pathlib import Path
from typing import Any
from momentum_core import has_long_upper_shadow,simple_moving_average,volume_ratio
class TechnicalError(RuntimeError):pass
def D(v:Any)->Decimal:
 try:return Decimal(str(v))
 except Exception as e:raise TechnicalError(f"invalid number: {v!r}") from e
def T(v):return None if v is None else format(v,"f")
def analyze_history(rows:list[dict[str,Any]],end_date:str)->dict[str,Any]:
 if len(rows)<21:raise TechnicalError(f"only {len(rows)} rows; need 21")
 dates=[str(x.get("trade_date") or "") for x in rows]
 if dates!=sorted(dates) or len(dates)!=len(set(dates)):raise TechnicalError("dates not unique ascending")
 if dates[-1]!=end_date:raise TechnicalError(f"latest {dates[-1]} != {end_date}")
 o=[D(x.get("open")) for x in rows];h=[D(x.get("high")) for x in rows];l=[D(x.get("low")) for x in rows];c=[D(x.get("close")) for x in rows];v=[D(x.get("volume_shares"))/1000 for x in rows]
 for a,b,d,e in zip(o,h,l,c):
  if min(a,b,d,e)<0 or b<max(a,e) or d>min(a,e):raise TechnicalError("invalid OHLC")
 if min(v)<0:raise TechnicalError("negative volume")
 ma={n:simple_moving_average(c,n) for n in (5,10,20)};ph=max(h[-21:-1]);vr=volume_ratio(int(v[-1]),[int(x) for x in v[:-1]],20)
 up={f"ma{n}_up":ma[n][-1]>ma[n][-2] for n in (5,10,20)};lu=has_long_upper_shadow(o[-1],h[-1],l[-1],c[-1]);fb=h[-1]>ph and c[-1]<=ph;hl=o[-1]>c[-2] and c[-1]<o[-1]
 risks=[]
 if lu:risks.append("長上影線")
 if hl:risks.append("高開走低")
 if fb:risks.append("假突破")
 if c[-1]<ma[5][-1]:risks.append("收盤跌破MA5")
 if c[-1]<ma[10][-1]:risks.append("收盤跌破MA10")
 return {"trade_date":end_date,"history_count":len(rows),"close":T(c[-1]),"ma5":T(ma[5][-1]),"ma10":T(ma[10][-1]),"ma20":T(ma[20][-1]),**up,"bullish_alignment":c[-1]>ma[5][-1]>ma[10][-1]>ma[20][-1],"close_above_ma5":c[-1]>ma[5][-1],"close_above_ma10":c[-1]>ma[10][-1],"close_above_ma20":c[-1]>ma[20][-1],"red_candle":c[-1]>o[-1],"prior_20d_high":T(ph),"distance_from_prior_20d_high_pct":T((c[-1]-ph)/ph*100) if ph>0 else None,"close_breakout_prior_20d_high":c[-1]>ph,"volume_ratio_20d":T(vr),"long_upper_shadow":lu,"high_open_low_close":hl,"false_breakout":fb,"risk_flags":risks}
def build(path:Path):
 doc=json.loads(path.read_text(encoding="utf-8"));day=str(doc.get("trade_date") or "");out=[];fails=list(doc.get("failures") or []);warn=list(doc.get("warnings") or [])
 for x in doc.get("records") or []:
  try:out.append({"market":x.get("market"),"stock_code":x.get("stock_code"),"stock_name":x.get("stock_name"),"technical":analyze_history(x.get("ohlcv_history") or [],day)})
  except TechnicalError as e:fails.append({"market":x.get("market"),"stock_code":x.get("stock_code"),"stock_name":x.get("stock_name"),"reason":str(e)});warn.append(f"{x.get('market')} {x.get('stock_code')}: {e}")
 return {"schema_version":"1.0","trade_date":day,"generated_at":datetime.now(timezone.utc).isoformat(),"requested_count":doc.get("requested_count"),"completed_count":len(out),"failed_count":len(fails),"warnings":warn,"failures":fails,"records":out}
def main():
 p=argparse.ArgumentParser();p.add_argument("--input",type=Path,required=True);p.add_argument("--output",type=Path,required=True);a=p.parse_args();r=build(a.input);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n",encoding="utf-8");print(f"wrote {len(r['records'])} technical records; {len(r['failures'])} failures")
if __name__=="__main__":main()
