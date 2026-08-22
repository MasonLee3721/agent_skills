import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts"))
from score_model import chip_score,continuity_score,foreign_score,investment_score,score_partial,technical_scores
class ScoreTests(unittest.TestCase):
 def strong_technical(self):
  return {"bullish_alignment":True,"ma5_up":True,"ma10_up":True,"ma20_up":True,"close_above_ma5":True,"close_above_ma10":True,"close_above_ma20":True,"close_breakout_prior_20d_high":True,"distance_from_prior_20d_high_pct":"1","red_candle":True,"volume_ratio_20d":"1.5","long_upper_shadow":False,"high_open_low_close":False,"false_breakout":False}
 def test_technical_caps_at_30(self):
  s=technical_scores(self.strong_technical());self.assertEqual(s["moving_averages"]["score"],15);self.assertEqual(s["breakout_volume"]["score"],15)
 def test_missing_chip_sections_are_zero_and_low_confidence(self):
  r=score_partial({"stock_code":"3008","technical":self.strong_technical()});self.assertEqual(r["total_score"],30);self.assertEqual(r["confidence"],"低");self.assertEqual(len(r["missing_sections"]),4)
 def test_false_breakout_deducts(self):
  t=self.strong_technical();t["false_breakout"]=True
  self.assertEqual(technical_scores(t)["breakout_volume"]["score"],9)
 def test_no_technical_data_never_passes(self):
  r=score_partial({"stock_code":"X"});self.assertEqual(r["total_score"],0);self.assertEqual(r["rating"],"不列入")
 def test_investment_without_market_rank_is_partial(self):
  r=investment_score("0.8");self.assertEqual(r["score"],11);self.assertEqual(r["status"],"partial")
 def test_estimated_chip_score_is_capped(self):
  r=chip_score(estimated_pct="4");self.assertEqual(r["score"],11);self.assertEqual(r["status"],"estimated")
 def test_continuity_acceleration(self):
  r=continuity_score(3,[100,200,300]);self.assertEqual(r["score"],18)
 def test_foreign_divergence_gets_no_sync_points(self):
  r=foreign_score([100,100,100],[-100,-100,-100]);self.assertEqual(r["score"],0);self.assertIn("法人分歧",r["reasons"])

if __name__=="__main__":unittest.main()
