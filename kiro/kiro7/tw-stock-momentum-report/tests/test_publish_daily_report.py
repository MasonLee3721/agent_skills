from __future__ import annotations
import json,subprocess,tempfile,unittest
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
from publish_daily_report import publish

class PublishDailyReportTests(unittest.TestCase):
 def git(self,args,cwd):
  return subprocess.run(["git",*args],cwd=cwd,text=True,capture_output=True,check=True).stdout
 def test_cross_repository_publish(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp);bare=root/"remote.git";seed=root/"seed";output=root/"output"
   self.git(["init","--bare",str(bare)],root);self.git(["init","-b","main",str(seed)],root)
   self.git(["config","user.name","Test"],seed);self.git(["config","user.email","test@example.com"],seed)
   (seed/"README.md").write_text("seed\n",encoding="utf-8");self.git(["add","README.md"],seed);self.git(["commit","-m","seed"],seed);self.git(["remote","add","origin",str(bare)],seed);self.git(["push","-u","origin","main"],seed)
   (output/"data").mkdir(parents=True);day="2026-08-21";stamp="20260821"
   (output/"data"/"daily_scores_latest.json").write_text(json.dumps({"trade_date":day}),encoding="utf-8")
   html=f"<html>{day}</html>";(output/"latest.html").write_text(html,encoding="utf-8");(output/f"tw_stock_momentum_report_{stamp}.html").write_text(html,encoding="utf-8")
   bundle={key:{"trade_date":day} for key in ("scores","prices","history")}
   (output/"data"/f"report_{stamp}.json").write_text(json.dumps(bundle),encoding="utf-8");(output/"data"/"daily_run_status.json").write_text(json.dumps({"status":"completed"}),encoding="utf-8")
   result=publish(output,str(bare),"main","reports")
   self.assertEqual(result["status"],"published")
   self.assertEqual(self.git(["show","main:reports/latest.html"],bare),html)
   self.assertEqual(publish(output,str(bare),"main","reports")["status"],"no_changes")

if __name__=="__main__":unittest.main()
