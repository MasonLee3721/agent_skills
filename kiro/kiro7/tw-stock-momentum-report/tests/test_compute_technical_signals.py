import sys,unittest
from datetime import date,timedelta
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts"))
from compute_technical_signals import TechnicalError,analyze_history
class TechnicalTests(unittest.TestCase):
 def rows(self):
  out=[]
  for i in range(21):
   close=100+i;out.append({"trade_date":(date(2026,7,30)+timedelta(days=i)).isoformat(),"open":str(close-1),"high":str(close+1),"low":str(close-2),"close":str(close),"volume_shares":str((1000+i*10)*1000)})
  return out
 def test_breakout_and_mas_use_prior_20_days(self):
  rows=self.rows();rows[-1].update({"open":"120","high":"122","low":"119","close":"121"});r=analyze_history(rows,"2026-08-19")
  self.assertTrue(r["close_breakout_prior_20d_high"]);self.assertTrue(r["bullish_alignment"]);self.assertTrue(r["ma5_up"]);self.assertEqual(r["prior_20d_high"],"120")
 def test_false_breakout_is_flagged(self):
  rows=self.rows();rows[-1].update({"open":"119","high":"122","low":"117","close":"119"})
  r=analyze_history(rows,"2026-08-19");self.assertTrue(r["false_breakout"]);self.assertIn("假突破",r["risk_flags"])
 def test_requires_21_rows(self):
  with self.assertRaises(TechnicalError):analyze_history(self.rows()[:20],"2026-08-18")
 def test_rejects_nonascending_dates(self):
  rows=self.rows();rows[-1]["trade_date"]=rows[-2]["trade_date"]
  with self.assertRaises(TechnicalError):analyze_history(rows,"2026-08-18")
if __name__=="__main__":unittest.main()
