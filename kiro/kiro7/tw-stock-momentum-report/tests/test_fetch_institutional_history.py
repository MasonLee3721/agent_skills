import json,sys,tempfile,unittest
from pathlib import Path
from datetime import date
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from fetch_institutional_history import HistoryError,cached_day,parse_tpex_history,roc_slash_to_iso
class HistoryTests(unittest.TestCase):
 def fixture(self):return json.loads((ROOT/'tests'/'fixtures'/'tpex_institutional_history.json').read_text(encoding='utf-8'))
 def test_tpex_historical_column_mapping(self):
  r=parse_tpex_history(self.fixture(),'u','t')[0]
  self.assertEqual((r.trade_date,r.stock_code),('2026-08-19','5678'));self.assertEqual(r.foreign_net_shares,80);self.assertEqual(r.sitc_net_shares,4)
 def test_roc_slash_validation(self):
  self.assertEqual(roc_slash_to_iso('115/08/19'),'2026-08-19')
  with self.assertRaises(HistoryError):roc_slash_to_iso('115/02/30')
 def test_short_row_fails(self):
  p=self.fixture();p['tables'][0]['data']=[['x']]
  with self.assertRaises(HistoryError):parse_tpex_history(p,'u','t')
 def test_duplicate_fails(self):
  p=self.fixture();p['tables'][0]['data']*=2
  with self.assertRaises(HistoryError):parse_tpex_history(p,'u','t')
 def test_failure_cache_prevents_repeated_official_hit(self):
  with tempfile.TemporaryDirectory() as d:
   with patch('fetch_institutional_history.fetch_day',side_effect=HistoryError('HTTP 307')) as fetch:
    with self.assertRaises(HistoryError):cached_day('TWSE',date(2026,8,19),Path(d),900)
    with self.assertRaisesRegex(HistoryError,'cached official failure'):cached_day('TWSE',date(2026,8,19),Path(d),900)
    self.assertEqual(fetch.call_count,1)
 def test_no_data_success_is_cached(self):
  with tempfile.TemporaryDirectory() as d:
   with patch('fetch_institutional_history.fetch_day',return_value=None) as fetch:
    self.assertIsNone(cached_day('TWSE',date(2026,8,18),Path(d),900));self.assertIsNone(cached_day('TWSE',date(2026,8,18),Path(d),900));self.assertEqual(fetch.call_count,1)
 def test_empty_holiday_table_is_not_a_trading_day(self):
  # Regression 2026-09-29: TPEx returned empty tables on 09-25/09-28 holidays, which were counted as trading days with missing rows.
  from fetch_institutional_history import collect
  from fetch_official_data import InstitutionalRecord
  def fake(market,day,*a,**k):
   if day.isoformat() in ('2026-09-25','2026-09-28'):return []
   return [InstitutionalRecord(day.isoformat(),'3324','雙鴻','TPEx',10,5,'s','u','t')]
  with tempfile.TemporaryDirectory() as d:
   t=Path(d)/'t.json';t.write_text(json.dumps({'trade_date':'2026-09-29','targets':[{'market':'TPEx','stock_code':'3324','stock_name':'雙鴻'}]}),encoding='utf-8')
   with patch('fetch_institutional_history.cached_day',side_effect=fake):r=collect(t,'2026-09-29',3)
  h=r['records'][0]['sitc_history'];self.assertEqual([x['trade_date'] for x in h],['2026-09-23','2026-09-24','2026-09-29']);self.assertFalse(any(x['missing'] for x in h));self.assertEqual(r['warnings'],[])

if __name__=='__main__':unittest.main()
