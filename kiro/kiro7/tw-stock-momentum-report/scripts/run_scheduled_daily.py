#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,subprocess,sys,time
from datetime import datetime,timezone
from pathlib import Path
RETRYABLE=("market quote dates differ","returned dates","HTTP Error 307","cached official failure","official fetch failed","history fetch failed","Temporary Redirect","timed out")
def retryable(text:str)->bool:return any(x.lower() in text.lower() for x in RETRYABLE)
def atomic_json(path:Path,doc:dict)->None:
 path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_suffix(".tmp");tmp.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8");tmp.replace(path)
def execute(output_dir:Path,attempts:int,interval_seconds:int,publish:bool=False)->int:
 if attempts<1 or interval_seconds<0:raise ValueError("invalid retry settings")
 runner=Path(__file__).resolve().parent/"run_daily_screen.py";status_path=output_dir/"data"/"daily_run_status.json";log_dir=output_dir/"logs";log_dir.mkdir(parents=True,exist_ok=True);started=datetime.now(timezone.utc);log_path=log_dir/f"daily_{started:%Y%m%dT%H%M%SZ}.log";events=[]
 for attempt in range(1,attempts+1):
  now=datetime.now(timezone.utc).isoformat();result=subprocess.run([sys.executable,str(runner),"--output-dir",str(output_dir)],text=True,capture_output=True);event={"attempt":attempt,"at":now,"returncode":result.returncode,"stdout":result.stdout.strip(),"stderr":result.stderr.strip()};events.append(event);log_path.write_text("\n\n".join(json.dumps(x,ensure_ascii=False) for x in events)+"\n",encoding="utf-8")
  if result.returncode==0:
   atomic_json(status_path,{"status":"completed","completed_at":datetime.now(timezone.utc).isoformat(),"attempts_used":attempt,"log_path":str(log_path)});print(result.stdout.strip())
   if publish:
    publisher=Path(__file__).resolve().parent/"publish_daily_report.py";published=subprocess.run([sys.executable,str(publisher),"--output-dir",str(output_dir)],text=True,capture_output=True)
    if published.returncode:print(published.stderr.strip(),file=sys.stderr);return 4
    print(published.stdout.strip())
   return 0
  message=result.stderr+"\n"+result.stdout
  if not retryable(message):atomic_json(status_path,{"status":"failed_non_retryable","failed_at":datetime.now(timezone.utc).isoformat(),"attempts_used":attempt,"last_error":message.strip(),"log_path":str(log_path)});print(message.strip(),file=sys.stderr);return 2
  if attempt<attempts:time.sleep(interval_seconds)
 atomic_json(status_path,{"status":"failed_retry_exhausted","failed_at":datetime.now(timezone.utc).isoformat(),"attempts_used":attempts,"last_error":events[-1]["stderr"],"log_path":str(log_path)});print(events[-1]["stderr"],file=sys.stderr);return 3
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--output-dir",type=Path,default=Path("output"));p.add_argument("--attempts",type=int,default=16);p.add_argument("--interval-seconds",type=int,default=900);p.add_argument("--publish",action="store_true");a=p.parse_args();return execute(a.output_dir,a.attempts,a.interval_seconds,a.publish)
if __name__=="__main__":raise SystemExit(main())
