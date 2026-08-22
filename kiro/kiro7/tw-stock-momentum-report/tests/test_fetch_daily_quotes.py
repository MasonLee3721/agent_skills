import json,sys,unittest
from unittest.mock import patch
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from fetch_daily_quotes import QuoteDataError,decimal_text,fetch_market,parse_tpex,parse_twse,parse_twse_mi_index
class QuoteTests(unittest.TestCase):
 def fixture(self,n):return json.loads((ROOT/'tests'/'fixtures'/n).read_text(encoding='utf-8'))
 def test_twse_volume_is_shares_and_prices_normalized(self):
  rows=parse_twse(self.fixture('twse_quotes.json'),'u','t');r=rows[0]
  self.assertEqual((r.trade_date,r.market,r.volume_shares),('2026-08-19','TWSE',3000500));self.assertEqual(r.close,'10.50');self.assertTrue(r.trading_status_ok)
 def test_suspended_or_no_trade_is_not_eligible(self):
  r=parse_twse(self.fixture('twse_quotes.json'),'u','t')[1]
  self.assertFalse(r.trading_status_ok);self.assertFalse(r.liquidity_status_ok);self.assertIsNone(r.close)
 def test_tpex_schema(self):
  r=parse_tpex(self.fixture('tpex_quotes.json'),'u','t')[0]
  self.assertEqual(r.stock_code,'5678');self.assertEqual(r.change,'-0.5');self.assertEqual(r.volume_shares,4000000)
 def test_ex_rights_only_marker_is_missing_change(self):
  self.assertIsNone(decimal_text('除息 '));self.assertIsNone(decimal_text('除權 '))
 def test_invalid_decimal_fails(self):
  with self.assertRaises(QuoteDataError):decimal_text('not-price')
 def test_duplicate_key_fails(self):
  payload=self.fixture('tpex_quotes.json')*2
  with self.assertRaises(QuoteDataError):parse_tpex(payload,'u','t')
 def mi_payload(self,day="20260821"):
  return {"stat":"OK","date":day,"tables":[{"fields":["證券代號","證券名稱","成交股數","成交筆數","成交金額","開盤價","最高價","最低價","收盤價","漲跌(+/-)","漲跌價差"],"data":[["2330","台積電","1,500","1","10","10","11","9","10.5","<p style= color:red>+</p>","0.5"]]}]}
 def test_mi_index_normalizes_and_validates_date(self):
  r=parse_twse_mi_index(self.mi_payload(),"2026-08-21","u","t")[0]
  self.assertEqual((r.trade_date,r.stock_code,r.volume_shares,r.change),("2026-08-21","2330",1500,"0.5"))
  with self.assertRaises(QuoteDataError):parse_twse_mi_index(self.mi_payload("20260820"),"2026-08-21","u","t")
 def test_twse_stale_snapshot_uses_official_mi_index(self):
  primary=self.fixture("twse_quotes.json")
  with patch("fetch_daily_quotes.fetch_json",side_effect=[(primary,"t1"),(self.mi_payload(),"t2")]) as fetch:
   rows=fetch_market("twse","2026-08-21")
  self.assertEqual({x.trade_date for x in rows},{"2026-08-21"});self.assertEqual(fetch.call_count,2)
if __name__=='__main__':unittest.main()
