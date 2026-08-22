import json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts"))
from build_daily_scores import DailyScoreError,build,keyed
class DailyScoreTests(unittest.TestCase):
 def test_duplicate_key_fails(self):
  with self.assertRaises(DailyScoreError):keyed([{"market":"TWSE","stock_code":"1"},{"market":"TWSE","stock_code":"1"}])
 def test_date_mismatch_fails_closed(self):
  with tempfile.TemporaryDirectory() as d:
   paths=[]
   for i,day in enumerate(["2026-08-20","2026-08-20","2026-08-19","2026-08-20"]):
    p=Path(d)/f"{i}.json";p.write_text(json.dumps({"trade_date":day,"records":[]}),encoding="utf-8");paths.append(p)
   with self.assertRaises(DailyScoreError):build(*paths)
 def test_missing_technical_is_zero_scored_and_does_not_abort(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);day='2026-08-21';key={'market':'TWSE','stock_code':'2330','stock_name':'台積電'}
   dataset={**key,'issued_shares':1000000,'investment_ratio_pct':'0.5','positive_ratio_rank':1,'volume_lots':5000,'paid_in_capital_twd':1000000000,'preselection':{'passed':True}}
   screened={**key,'sitc_buy_streak':3,'aggressive_passed':True,'conservative_passed':True}
   hist={**key,'sitc_history':[{'sitc_net_shares':1000,'foreign_net_shares':1000},{'sitc_net_shares':1000,'foreign_net_shares':1000},{'sitc_net_shares':1000,'foreign_net_shares':1000}]}
   docs=[{'trade_date':day,'records':[dataset]},{'trade_date':day,'records':[screened]},{'trade_date':day,'records':[hist]},{'trade_date':day,'records':[],'failures':[{**key,'reason':'HTTP 520'}]}]
   ps=[]
   for i,doc in enumerate(docs):
    q=root/f'{i}.json';q.write_text(json.dumps(doc),encoding='utf-8');ps.append(q)
   result=build(*ps);row=result['records'][0]
  self.assertEqual(result['counts']['technical_missing'],1);self.assertEqual(row['sections']['moving_averages']['score'],0);self.assertEqual(row['confidence'],'低');self.assertIsNone(row['trading_plan']);self.assertEqual(row['technical_error'],'HTTP 520')
if __name__=="__main__":unittest.main()
