import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts"))
from fetch_finmind_institutional_history import FinMindError,normalize
class FinMindTests(unittest.TestCase):
 def payload(self):
  return {"status":200,"data":[{"date":"2026-08-18","stock_id":"3008","buy":100,"sell":40,"name":"Foreign_Investor"},{"date":"2026-08-18","stock_id":"3008","buy":30,"sell":10,"name":"Investment_Trust"},{"date":"2026-08-19","stock_id":"3008","buy":80,"sell":100,"name":"Foreign_Investor"},{"date":"2026-08-19","stock_id":"3008","buy":50,"sell":5,"name":"Investment_Trust"},{"date":"2026-08-20","stock_id":"3008","buy":999,"sell":0,"name":"Investment_Trust"}]}
 def test_normalizes_net_shares_and_truncates_future(self):
  h=normalize(self.payload(),"3008","2026-08-19",3);self.assertEqual(len(h),2);self.assertEqual(h[-1]["foreign_net_shares"],-20);self.assertEqual(h[-1]["sitc_net_shares"],45);self.assertFalse(h[-1]["missing"])
 def test_missing_category_is_explicit(self):
  p=self.payload();p["data"]=[p["data"][0]];self.assertTrue(normalize(p,"3008","2026-08-19",3)[0]["missing"])
 def test_duplicate_category_fails(self):
  p=self.payload();p["data"].append(dict(p["data"][0]));
  with self.assertRaises(FinMindError):normalize(p,"3008","2026-08-19",3)
 def test_identity_mismatch_fails(self):
  p=self.payload();p["data"][0]["stock_id"]="9999"
  with self.assertRaises(FinMindError):normalize(p,"3008","2026-08-19",3)
if __name__=="__main__":unittest.main()
