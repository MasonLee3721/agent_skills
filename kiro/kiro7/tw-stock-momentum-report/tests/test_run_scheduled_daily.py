import sys,tempfile,unittest
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
if __name__=="__main__":unittest.main()
