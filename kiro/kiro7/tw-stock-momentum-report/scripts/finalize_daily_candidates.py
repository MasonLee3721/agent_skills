#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from datetime import datetime,timezone
from pathlib import Path
from typing import Any
from momentum_core import trailing_positive_streak
class FinalizeError(RuntimeError):pass
def classify(history:list[dict[str,Any]])->dict[str,Any]:
 if len(history)<3:raise FinalizeError("at least 3 institutional days required")
 values=[x.get("sitc_net_shares") for x in history];foreign=[x.get("foreign_net_shares") for x in history]
 if any(v is None for v in values[-3:]) or any(v is None for v in foreign[-3:]):raise FinalizeError("latest 3 institutional days contain missing values")
 streak=trailing_positive_streak(values);cooling=len(values)>=2 and values[-1]>0 and values[-2]>0 and values[-1]<=values[-2]*0.5
 return {"sitc_buy_streak":streak,"aggressive_passed":streak>=1,"conservative_passed":streak>=3,"sitc_net_shares_3d":values[-3:],"sitc_net_shares_3d_sum":sum(values[-3:]),"foreign_net_shares_3d":foreign[-3:],"foreign_net_shares_3d_sum":sum(foreign[-3:]),"foreign_sync_latest":values[-1]>0 and foreign[-1]>0,"buying_cooling":cooling,"chip_flags":["買盤降溫"] if cooling else []}
def finalize(dataset_path:Path,history_path:Path)->dict[str,Any]:
 dataset=json.loads(dataset_path.read_text(encoding="utf-8"));history=json.loads(history_path.read_text(encoding="utf-8"));day=dataset.get("trade_date")
 if history.get("trade_date")!=day:raise FinalizeError("dataset/history date mismatch")
 base={(x["market"],x["stock_code"]):x for x in dataset.get("records",[]) if x.get("preselection",{}).get("passed")};rows=[]
 for h in history.get("records",[]):
  key=(h.get("market"),h.get("stock_code"))
  if key not in base:raise FinalizeError(f"history target absent from preselection: {key}")
  x=base[key];derived=classify(h.get("sitc_history") or []);rows.append({"market":x["market"],"stock_code":x["stock_code"],"stock_name":x["stock_name"],"trade_date":day,"investment_ratio_pct":x["investment_ratio_pct"],"positive_ratio_rank":x["positive_ratio_rank"],"sitc_net_shares":x["sitc_net_shares"],"foreign_net_shares":x["foreign_net_shares"],"volume_lots":x["volume_lots"],"paid_in_capital_twd":x["paid_in_capital_twd"],**derived})
 if len(rows)!=len(base):raise FinalizeError(f"history count {len(rows)} differs from preselection {len(base)}")
 rows.sort(key=lambda x:(-x["sitc_buy_streak"],x["positive_ratio_rank"],x["stock_code"]));return {"schema_version":"1.0","trade_date":day,"generated_at":datetime.now(timezone.utc).isoformat(),"thresholds":{"aggressive_min_streak":1,"conservative_min_streak":3,"buying_cooling_latest_vs_previous_max_ratio":0.5},"counts":{"preselected":len(rows),"aggressive":sum(x["aggressive_passed"] for x in rows),"conservative":sum(x["conservative_passed"] for x in rows),"buying_cooling":sum(x["buying_cooling"] for x in rows)},"records":rows}
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--dataset",type=Path,required=True);p.add_argument("--history",type=Path,required=True);p.add_argument("--output",type=Path,required=True);a=p.parse_args();r=finalize(a.dataset,a.history);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n",encoding="utf-8");print(json.dumps(r["counts"],ensure_ascii=False));return 0
if __name__=="__main__":
 try:raise SystemExit(main())
 except (FinalizeError,OSError,json.JSONDecodeError) as exc:print(f"ERROR: {exc}",file=__import__("sys").stderr);raise SystemExit(2)
