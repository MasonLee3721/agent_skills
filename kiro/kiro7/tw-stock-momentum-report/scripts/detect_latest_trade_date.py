#!/usr/bin/env python3
from __future__ import annotations
import json
from datetime import datetime,timezone
from fetch_daily_quotes import fetch_market as fetch_quote_market
from fetch_official_data import fetch_market as fetch_institutional_market
class TradeDateError(RuntimeError):pass
def singleton_date(records,label:str)->str:
 dates={x.trade_date for x in records}
 if len(dates)!=1:raise TradeDateError(f"{label} returned dates {sorted(dates)}")
 return next(iter(dates))
def detect()->dict:
 tpex_date=singleton_date(fetch_quote_market("tpex"),"tpex quotes");quote_dates={"twse":singleton_date(fetch_quote_market("twse",tpex_date),"twse quotes"),"tpex":tpex_date}
 if len(set(quote_dates.values()))!=1:raise TradeDateError(f"market quote dates differ: {quote_dates}")
 day=quote_dates["twse"];institutional_dates={m:singleton_date(fetch_institutional_market(m,day),f"{m} institutional") for m in ("twse","tpex")}
 if set(institutional_dates.values())!={day}:raise TradeDateError(f"institutional dates differ from quotes: {institutional_dates} vs {day}")
 return {"trade_date":day,"detected_at":datetime.now(timezone.utc).isoformat(),"quote_dates":quote_dates,"institutional_dates":institutional_dates}
def main()->int:print(json.dumps(detect(),ensure_ascii=False));return 0
if __name__=="__main__":
 try:raise SystemExit(main())
 except TradeDateError as exc:print(f"ERROR: {exc}",file=__import__("sys").stderr);raise SystemExit(2)
