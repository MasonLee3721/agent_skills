import sys
import unittest
from copy import deepcopy
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from build_dataset import DatasetError, build_dataset


class DatasetTests(unittest.TestCase):
    def documents(self):
        inst={'requested_trade_date':'2026-08-19','records':[
          {'trade_date':'2026-08-19','market':'TWSE','stock_code':'1234','stock_name':'甲','sitc_net_shares':400000,'foreign_net_shares':100000,'source_url':'i',
           'sitc_history':[{'trade_date':'2026-08-18','sitc_net_shares':100000},{'trade_date':'2026-08-19','sitc_net_shares':400000}]},
          {'trade_date':'2026-08-19','market':'TWSE','stock_code':'0050','stock_name':'ETF','sitc_net_shares':0,'foreign_net_shares':0,'source_url':'i'}]}
        companies={'data_date':'2026-08-18','records':[
          {'market':'TWSE','stock_code':'1234','stock_name':'甲','security_type':'common_stock','paid_in_capital_twd':1000000000,'issued_shares':100000000,'source_url':'c'},
          {'market':'TWSE','stock_code':'0050','stock_name':'ETF','security_type':'etf','paid_in_capital_twd':1000000,'issued_shares':100000,'source_url':'c'},
          {'market':'TPEx','stock_code':'5678','stock_name':'缺資料','security_type':'common_stock','paid_in_capital_twd':1000000,'issued_shares':100000,'source_url':'c'}]}
        quotes={'trade_date':'2026-08-19','records':[
          {'trade_date':'2026-08-19','market':'TWSE','stock_code':'1234','volume_shares':3000000,'open':'10','high':'11','low':'9','close':'10.5','trading_status_ok':True,'liquidity_status_ok':True,'source_url':'q'},
          {'trade_date':'2026-08-19','market':'TWSE','stock_code':'0050','volume_shares':5000000,'open':'10','high':'11','low':'9','close':'10','trading_status_ok':True,'liquidity_status_ok':True,'source_url':'q'}]}
        return inst,companies,quotes

    def test_builds_auditable_dataset_and_exclusions(self):
        result=build_dataset(*self.documents(),'2026-08-19')
        self.assertEqual(result['counts']['company_universe'],3)
        self.assertEqual(result['counts']['analyzable'],1)
        row=result['records'][0]
        self.assertEqual(row['investment_ratio_pct'],'0.400')
        self.assertEqual(row['consecutive_sitc_buy_days'],2)
        self.assertTrue(row['preselection']['passed'])
        self.assertFalse(row['history_required'])
        self.assertTrue(row['screening']['aggressive']['passed'])
        self.assertFalse(row['screening']['conservative']['passed'])
        excluded={e['stock_code']:e['reasons'] for e in result['exclusions']}
        self.assertIn('non_common_stock',excluded['0050'])
        self.assertEqual(set(excluded['5678']),{'missing_institutional','missing_quote'})

    def test_date_mismatch_fails_closed(self):
        inst,companies,quotes=self.documents(); quotes['trade_date']='2026-08-18'
        with self.assertRaises(DatasetError): build_dataset(inst,companies,quotes,'2026-08-19')

    def test_row_date_mismatch_fails_closed(self):
        inst,companies,quotes=self.documents(); inst['records'][0]['trade_date']='2026-08-18'
        with self.assertRaises(DatasetError): build_dataset(inst,companies,quotes,'2026-08-19')

    def test_duplicate_key_is_rejected(self):
        inst,companies,quotes=self.documents(); companies['records'].append(deepcopy(companies['records'][0]))
        with self.assertRaises(DatasetError): build_dataset(inst,companies,quotes,'2026-08-19')

    def test_missing_current_history_never_claims_streak(self):
        inst,companies,quotes=self.documents(); inst['records'][0]['sitc_history']=[{'trade_date':'2026-08-18','sitc_net_shares':1}]
        result=build_dataset(inst,companies,quotes,'2026-08-19')
        row=result['records'][0]
        self.assertIsNone(row['consecutive_sitc_buy_days'])
        self.assertTrue(row['preselection']['passed'])
        self.assertTrue(row['history_required'])
        self.assertFalse(row['screening']['aggressive']['passed'])

    def test_fractional_lot_volume_does_not_round_up(self):
        inst,companies,quotes=self.documents(); quotes['records'][0]['volume_shares']=3000500
        result=build_dataset(inst,companies,quotes,'2026-08-19')
        self.assertEqual(result['records'][0]['volume_lots'],'3000.5')
        self.assertTrue(result['records'][0]['preselection']['passed'])
        self.assertTrue(result['records'][0]['screening']['aggressive']['passed'])


if __name__=='__main__': unittest.main()
