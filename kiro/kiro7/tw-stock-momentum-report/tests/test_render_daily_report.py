import json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts"))
from render_daily_report import ReportError,render
class RenderTests(unittest.TestCase):
 def test_date_mismatch_fails(self):
  with tempfile.TemporaryDirectory() as d:
   ps=[]
   for i,day in enumerate(["2026-08-20","2026-08-19","2026-08-20"]):
    p=Path(d)/f"{i}.json";p.write_text(json.dumps({"trade_date":day}),encoding="utf-8");ps.append(p)
   with self.assertRaises(ReportError):render(*ps,Path(d)/"out")
 def test_writes_machine_readable_report_bundle(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);ps=[]
   docs=[{'trade_date':'2026-08-21','records':[],'counts':{'strong':0,'watch':0},'warnings':[]},{'trade_date':'2026-08-21','records':[]},{'trade_date':'2026-08-21','records':[]}]
   for i,doc in enumerate(docs):
    x=root/f'{i}.json';x.write_text(json.dumps(doc),encoding='utf-8');ps.append(x)
   latest,dated=render(*ps,root/'out');report=root/'out'/'data'/'report_20260821.json'
   self.assertTrue(latest.exists());self.assertTrue(dated.exists());self.assertTrue(report.exists());self.assertIn('scores',json.loads(report.read_text()));html=latest.read_text();self.assertIn('\"":"&quot;',html);self.assertNotIn('""":"&quot;',html);self.assertIn('class=\\"chart-toggle\\"',html);self.assertIn("addEventListener(\"click\"",html);self.assertNotIn("onclick=\"toggleChart",html);self.assertNotIn("cdn.jsdelivr.net",html);self.assertNotIn("__ECHARTS__",html);self.assertIn('id="sync"',html);self.assertIn("當日外資張",html);self.assertIn("法人同步",html);self.assertIn("latestInst",html);self.assertNotIn('onclick="drawTable()"',html);self.assertIn("投本比強度",html);self.assertIn("reason-section",html);self.assertIn("prettyReason",html);self.assertIn('id="showMethod"',html);self.assertIn('id="methodModal"',html);self.assertIn("篩選與評分機制",html);self.assertIn("closeMethod",html);self.assertIn('id="reasonModal"',html);self.assertIn("reason-toggle",html);self.assertIn("closeReason",html);self.assertIn("reasonHtml",html);self.assertNotIn("<details><summary>查看</summary>",html);self.assertIn('id="chartModal"',html);self.assertIn('id="chartCanvas"',html);self.assertIn("closeChart",html);self.assertIn("chartInstance.dispose()",html);self.assertNotIn('id="charts"',html)
if __name__=="__main__":unittest.main()
