import sys,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts"))
from run_daily_screen import DailyScreenError,output_paths,run
class DailyRunnerTests(unittest.TestCase):
 def test_paths_are_date_scoped(self):
  p=output_paths(Path("output"),"2026-08-20");self.assertEqual(p["dataset"],Path("output/data/daily_dataset_20260820.json"));self.assertEqual(len(set(p.values())),11);self.assertIn("screened",p);self.assertIn("technical",p);self.assertIn("scores",p);self.assertIn("report",p)
 def test_failed_step_stops_pipeline(self):
  with patch("run_daily_screen.subprocess.run") as proc:
   proc.return_value.returncode=2
   with self.assertRaises(DailyScreenError):run(["python","bad.py"])
if __name__=="__main__":unittest.main()
