#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,subprocess,sys
from datetime import date
from pathlib import Path
from detect_latest_trade_date import TradeDateError,detect
class DailyScreenError(RuntimeError):pass
def run(command:list[str])->None:
 result=subprocess.run(command,text=True)
 if result.returncode!=0:raise DailyScreenError(f"step failed with exit {result.returncode}: {command[1]}")
def output_paths(root:Path,day:str)->dict[str,Path]:
 stamp=day.replace("-","")
 data=root/"data";return {"institutional":data/f"daily_institutional_{stamp}.json","companies":data/f"company_universe_{stamp}.json","quotes":data/f"daily_quotes_{stamp}.json","dataset":data/f"daily_dataset_{stamp}.json","candidates":data/f"daily_candidates_{stamp}.json","history":data/f"daily_institutional_history_{stamp}.json","screened":data/f"daily_screened_candidates_{stamp}.json","prices":data/f"daily_price_history_{stamp}.json","technical":data/f"daily_technical_signals_{stamp}.json","scores":data/f"daily_scores_{stamp}.json","report":root/f"tw_stock_momentum_report_{stamp}.html"}
def execute(day:str,root:Path)->dict:
 date.fromisoformat(day);paths=output_paths(root,day);base=Path(__file__).resolve().parent;py=sys.executable
 run([py,str(base/"fetch_official_data.py"),"--market","all","--date",day,"--output",str(paths["institutional"])])
 run([py,str(base/"fetch_company_universe.py"),"--market","all","--output",str(paths["companies"])])
 run([py,str(base/"fetch_daily_quotes.py"),"--market","all","--date",day,"--output",str(paths["quotes"])])
 run([py,str(base/"build_dataset.py"),"--institutional",str(paths["institutional"]),"--companies",str(paths["companies"]),"--quotes",str(paths["quotes"]),"--date",day,"--output",str(paths["dataset"])])
 run([py,str(base/"select_history_targets.py"),"--dataset",str(paths["dataset"]),"--institutional-days","10","--price-days","120","--output",str(paths["candidates"])])
 dataset=json.loads(paths["dataset"].read_text(encoding="utf-8"));latest=root/"data"/"daily_candidates_latest.json";latest.write_text(paths["candidates"].read_text(encoding="utf-8"),encoding="utf-8");history_status="completed";history_error=None;screened_counts=None
 try:
  run([py,str(base/"fetch_institutional_history.py"),"--targets",str(paths["candidates"]),"--end-date",day,"--days","10","--cache-dir",str(root/"cache"/"institutional"),"--failure-cooldown-seconds","900","--output",str(paths["history"])])
  run([py,str(base/"finalize_daily_candidates.py"),"--dataset",str(paths["dataset"]),"--history",str(paths["history"]),"--output",str(paths["screened"])])
  screened_doc=json.loads(paths["screened"].read_text(encoding="utf-8"));screened_counts=screened_doc["counts"]
  (root/"data"/"daily_screened_candidates_latest.json").write_text(paths["screened"].read_text(encoding="utf-8"),encoding="utf-8")
 except DailyScreenError as exc:history_status="failed";history_error=str(exc)
 technical_status="completed";technical_error=None
 try:
  run([py,str(base/"fetch_price_history.py"),"--targets",str(paths["candidates"]),"--end-date",day,"--days","120","--cache-dir",str(root/"cache"/"price"),"--daily-quotes",str(paths["quotes"]),"--output",str(paths["prices"])])
  run([py,str(base/"compute_technical_signals.py"),"--input",str(paths["prices"]),"--output",str(paths["technical"])])
  if history_status=="completed":
   run([py,str(base/"build_daily_scores.py"),"--dataset",str(paths["dataset"]),"--screened",str(paths["screened"]),"--history",str(paths["history"]),"--technical",str(paths["technical"]),"--output",str(paths["scores"])])
   (root/"data"/"daily_scores_latest.json").write_text(paths["scores"].read_text(encoding="utf-8"),encoding="utf-8")
 except DailyScreenError as exc:technical_status="failed";technical_error=str(exc)
 report_status="skipped";report_error=None
 if history_status=="completed" and technical_status=="completed" and paths["scores"].exists():
  try:
   run([py,str(base/"render_daily_report.py"),"--scores",str(paths["scores"]),"--prices",str(paths["prices"]),"--history",str(paths["history"]),"--output-dir",str(root)])
   report_status="completed"
  except DailyScreenError as exc:report_status="failed";report_error=str(exc)
 return {"trade_date":day,"preselection_counts":dataset["counts"],"screened_counts":screened_counts,"history_status":history_status,"history_error":history_error,"technical_status":technical_status,"technical_error":technical_error,"report_status":report_status,"report_error":report_error,"paths":{k:str(v) for k,v in paths.items()}}
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--date",help="completed exchange date YYYY-MM-DD; omitted means detect from four official sources");p.add_argument("--output-dir",type=Path,default=Path("output"));a=p.parse_args();day=a.date or detect()["trade_date"];result=execute(day,a.output_dir);print(json.dumps(result,ensure_ascii=False));return 0
if __name__=="__main__":
 try:raise SystemExit(main())
 except (DailyScreenError,TradeDateError,ValueError,OSError,json.JSONDecodeError) as exc:print(f"ERROR: {exc}",file=sys.stderr);raise SystemExit(2)
