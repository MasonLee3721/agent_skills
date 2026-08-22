import json,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from fetch_company_universe import CompanyDataError,par_value,parse_tpex,parse_twse
class CompanyTests(unittest.TestCase):
 def fixture(self,name):return json.loads((ROOT/'tests'/'fixtures'/name).read_text(encoding='utf-8'))
 def test_twse_uses_actual_issue_shares_and_par(self):
  r=parse_twse(self.fixture('twse_company.json'),'u','t')[0]
  self.assertEqual((r.market,r.stock_code,r.data_date),('TWSE','1234','2026-08-19'))
  self.assertEqual(r.issued_shares,100000000);self.assertEqual(r.par_value_twd,'5.0000');self.assertFalse(r.issued_shares_is_estimated)
 def test_tpex_preserves_no_par_without_guessing(self):
  r=parse_tpex(self.fixture('tpex_company.json'),'u','t')[0]
  self.assertEqual(r.issued_shares,75000000);self.assertIsNone(r.par_value_twd);self.assertFalse(r.issued_shares_is_estimated)
 def test_par_parser_does_not_invent_value(self):
  self.assertIsNone(par_value('無面額'));self.assertIsNone(par_value(''))
 def test_duplicate_is_rejected(self):
  payload=self.fixture('twse_company.json')*2
  with self.assertRaises(CompanyDataError):parse_twse(payload,'u','t')
 def test_missing_issue_shares_remains_null(self):
  payload=self.fixture('tpex_company.json');payload[0]['IssueShares']='N/A'
  self.assertIsNone(parse_tpex(payload,'u','t')[0].issued_shares)
if __name__=='__main__':unittest.main()
