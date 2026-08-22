import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT/'scripts'))
from select_history_targets import TargetError,select_targets

class TargetTests(unittest.TestCase):
 def test_only_preselected_become_history_targets(self):
  dataset={'trade_date':'2026-08-19','records':[
   {'market':'TWSE','stock_code':'1234','stock_name':'甲','preselection':{'passed':True}},
   {'market':'TPEx','stock_code':'5678','stock_name':'乙','preselection':{'passed':False}}]}
  result=select_targets(dataset)
  self.assertEqual(result['target_count'],1); self.assertEqual(result['targets'][0]['stock_code'],'1234')
  self.assertEqual(result['targets'][0]['institutional_history_days'],10)
  self.assertEqual(result['targets'][0]['price_history_days'],120)
 def test_rejects_windows_below_report_minimum(self):
  with self.assertRaises(TargetError): select_targets({'records':[]},2,120)
  with self.assertRaises(TargetError): select_targets({'records':[]},10,59)
 def test_missing_preselection_fails_closed(self):
  with self.assertRaises(TargetError): select_targets({'records':[{'market':'TWSE','stock_code':'1234'}]})
if __name__=='__main__': unittest.main()
