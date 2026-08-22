import sys,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts"))
from detect_latest_trade_date import TradeDateError,detect,singleton_date
class DetectDateTests(unittest.TestCase):
 def rows(self,day):return [SimpleNamespace(trade_date=day)]
 def test_singleton_rejects_mixed_dates(self):
  with self.assertRaises(TradeDateError):singleton_date(self.rows("2026-08-19")+self.rows("2026-08-20"),"x")
 def test_four_sources_must_agree(self):
  with patch("detect_latest_trade_date.fetch_quote_market",side_effect=lambda m,*args:self.rows("2026-08-20")),patch("detect_latest_trade_date.fetch_institutional_market",side_effect=lambda m,d:self.rows(d)):
   self.assertEqual(detect()["trade_date"],"2026-08-20")
 def test_market_quote_mismatch_fails_before_institutional(self):
  with patch("detect_latest_trade_date.fetch_quote_market",side_effect=[self.rows("2026-08-19"),self.rows("2026-08-20")]):
   with self.assertRaises(TradeDateError):detect()
if __name__=="__main__":unittest.main()
