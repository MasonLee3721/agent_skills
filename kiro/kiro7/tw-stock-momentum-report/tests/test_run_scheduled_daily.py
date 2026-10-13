import json,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts"))
from run_scheduled_daily import execute,retryable
class ScheduledTests(unittest.TestCase):
 def test_retryable_transient_errors(self):
  self.assertTrue(retryable("market quote dates differ"));self.assertTrue(retryable("HTTP Error 307"));self.assertFalse(retryable("duplicate stock key"))
 def test_non_retryable_stops_immediately(self):
  with tempfile.TemporaryDirectory() as d,patch("run_scheduled_daily.subprocess.run") as proc:
   proc.return_value.returncode=2;proc.return_value.stdout="";proc.return_value.stderr="duplicate stock key";self.assertEqual(execute(Path(d),4,0),2);self.assertEqual(proc.call_count,1)
 def test_retry_then_success(self):
  with tempfile.TemporaryDirectory() as d,patch("run_scheduled_daily.subprocess.run") as proc:
   fail=type("R",(),{"returncode":2,"stdout":"","stderr":"market quote dates differ"})();ok=type("R",(),{"returncode":0,"stdout":"done","stderr":""})();proc.side_effect=[fail,ok];self.assertEqual(execute(Path(d),2,0),0);self.assertEqual(proc.call_count,2)
 def _status(self,d):return json.loads((Path(d)/"data"/"daily_run_status.json").read_text(encoding="utf-8"))
 def test_publish_failure_is_not_completed(self):
  with tempfile.TemporaryDirectory() as d,patch("run_scheduled_daily.subprocess.run") as proc:
   ok=type("R",(),{"returncode":0,"stdout":"done","stderr":""})();bad=type("R",(),{"returncode":2,"stdout":"","stderr":"push rejected"})();proc.side_effect=[ok,bad]
   self.assertEqual(execute(Path(d),1,0,publish=True),4);s=self._status(d);self.assertEqual(s["status"],"failed_publish");self.assertIn("push rejected",s["last_error"])
 def test_publish_pending_before_publish_then_completed(self):
  seen=[]
  with tempfile.TemporaryDirectory() as d:
   ok=type("R",(),{"returncode":0,"stdout":"done","stderr":""})();pub=type("R",(),{"returncode":0,"stdout":'{"status": "published", "commit": "abc"}',"stderr":""})()
   def fake(args,**kw):
    if "publish_daily_report.py" in args[1]:seen.append(self._status(d)["status"]);return pub
    return ok
   with patch("run_scheduled_daily.subprocess.run",side_effect=fake):self.assertEqual(execute(Path(d),1,0,publish=True),0)
   self.assertEqual(seen,["publish_pending"]);s=self._status(d);self.assertEqual((s["status"],s["commit"]),("completed","abc"))
if __name__=="__main__":unittest.main()
