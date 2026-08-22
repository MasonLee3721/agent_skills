#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
DEFAULT_REPOSITORY="https://github.com/MasonLee3721/kiro-notes.git"
DEFAULT_BRANCH="master"
DEFAULT_SUBDIR="kiro7_\u97cb\u5c0f\u5bf6/tw-stock-momentum-report/output"
class PublishError(RuntimeError):pass
def command(args:list[str],cwd:Path|None=None,check:bool=True)->subprocess.CompletedProcess[str]:
 result=subprocess.run(args,cwd=cwd,text=True,capture_output=True)
 if check and result.returncode:raise PublishError((result.stderr or result.stdout).strip())
 return result
def validate(output_dir:Path)->tuple[str,list[tuple[Path,Path]]]:
 scores=output_dir/"data"/"daily_scores_latest.json";latest=output_dir/"latest.html"
 if not scores.exists() or not latest.exists():raise PublishError("latest score JSON or HTML is missing")
 doc=json.loads(scores.read_text(encoding="utf-8"));day=str(doc.get("trade_date") or "")
 if len(day)!=10:raise PublishError("invalid latest trade_date")
 stamp=day.replace("-","");dated=output_dir/f"tw_stock_momentum_report_{stamp}.html";report=output_dir/"data"/f"report_{stamp}.json";status=output_dir/"data"/"daily_run_status.json"
 for path in (dated,report,status):
  if not path.exists():raise PublishError(f"missing publish artifact: {path}")
 bundle=json.loads(report.read_text(encoding="utf-8"));dates={bundle.get(key,{}).get("trade_date") for key in ("scores","prices","history")}
 if dates!={day}:raise PublishError(f"report dates differ: {dates}")
 html=latest.read_text(encoding="utf-8")
 if day not in html or "__DATA__" in html or "__ECHARTS__" in html:raise PublishError("latest HTML failed validation")
 return day,[(latest,Path("latest.html")),(dated,Path(dated.name)),(report,Path("data")/report.name),(status,Path("data")/status.name)]
def publish(output_dir:Path,repository:str=DEFAULT_REPOSITORY,branch:str=DEFAULT_BRANCH,subdir:str=DEFAULT_SUBDIR)->dict:
 day,files=validate(output_dir.resolve())
 if not repository or not branch or not subdir:raise PublishError("repository, branch and subdir are required")
 with tempfile.TemporaryDirectory(prefix="momentum-publish-") as temp:
  checkout=Path(temp)/"repo";command(["git","clone","--depth","1","--branch",branch,repository,str(checkout)]);command(["git","config","user.name","FangYi Report Bot"],checkout);command(["git","config","user.email","MasonLee3721@users.noreply.github.com"],checkout);target=checkout/subdir
  for source,relative in files:
   destination=target/relative;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,destination)
  relative_target=target.relative_to(checkout);command(["git","add","--",str(relative_target)],checkout)
  if command(["git","diff","--cached","--quiet","--"],checkout,check=False).returncode==0:return {"status":"no_changes","trade_date":day,"branch":branch}
  command(["git","commit","-m",f"data: publish momentum report {day}"],checkout);command(["git","push","origin",branch],checkout);sha=command(["git","rev-parse","HEAD"],checkout).stdout.strip()
 return {"status":"published","trade_date":day,"branch":branch,"commit":sha}
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--output-dir",type=Path,default=Path("output"));p.add_argument("--repository",default=DEFAULT_REPOSITORY);p.add_argument("--branch",default=DEFAULT_BRANCH);p.add_argument("--subdir",default=DEFAULT_SUBDIR);a=p.parse_args()
 try:print(json.dumps(publish(a.output_dir,a.repository,a.branch,a.subdir),ensure_ascii=False));return 0
 except (PublishError,OSError,json.JSONDecodeError) as exc:print(f"ERROR: {exc}",file=__import__("sys").stderr);return 2
if __name__=="__main__":raise SystemExit(main())
