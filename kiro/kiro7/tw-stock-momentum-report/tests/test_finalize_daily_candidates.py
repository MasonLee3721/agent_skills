import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts"))
from finalize_daily_candidates import FinalizeError,classify
class FinalizeTests(unittest.TestCase):
 def hist(self,sitc,foreign=None):
  foreign=foreign or [1]*len(sitc);return [{"sitc_net_shares":a,"foreign_net_shares":b} for a,b in zip(sitc,foreign)]
 def test_modes(self):
  r=classify(self.hist([-1,2,3,4]));self.assertEqual(r["sitc_buy_streak"],3);self.assertTrue(r["aggressive_passed"]);self.assertTrue(r["conservative_passed"])
 def test_aggressive_only(self):
  r=classify(self.hist([2,-1,5]));self.assertEqual(r["sitc_buy_streak"],1);self.assertTrue(r["aggressive_passed"]);self.assertFalse(r["conservative_passed"])
 def test_cooling_boundary(self):
  self.assertTrue(classify(self.hist([1,100,50]))["buying_cooling"]);self.assertFalse(classify(self.hist([1,100,51]))["buying_cooling"])
 def test_missing_fails(self):
  with self.assertRaises(FinalizeError):classify(self.hist([1,None,3]))
if __name__=="__main__":unittest.main()
