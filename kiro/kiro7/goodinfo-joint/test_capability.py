"""
test_capability.py - AST 執行期能力檢驗與命名空間隔離單元測試 (goodinfo-joint)
測試涵蓋 7 大情境：
1. 正向案例 (包含 os.environ.get('CHART_SCRIPT') 或 os.environ['CHART_SCRIPT'])
2. 能力缺失案例 (無 CHART_SCRIPT 邏輯)
3. 純註解/假陽性案例 (僅在註解中或 fake.environ 出現)
4. 語法錯誤案例 (無效 Python 語法)
5. 模組載入零副作用測試 (import 0 次 subprocess.run 呼叫)
6. main() 控制流 Smoke Test (在安全 Mock 下驗證 main 執行與 Temp 隔離)
7. main() 步驟失敗 Exit Non-Zero 測試 (驗證錯誤傳播)
"""
import unittest
import sys
import importlib.util
from pathlib import Path
from unittest.mock import patch, MagicMock

class TestScraperCapabilityAST(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        """採用獨特模組標籤 + 在 patch 監控下動態載入，杜絕頂層 Import 洩漏與命名空間污染"""
        cls.RUN_PY_PATH = Path(__file__).resolve().parent / "run.py"
        with patch("subprocess.run") as mock_sub:
            cls.spec = importlib.util.spec_from_file_location("goodinfo_joint_run_module", cls.RUN_PY_PATH)
            cls.goodinfo_joint_run = importlib.util.module_from_spec(cls.spec)
            cls.spec.loader.exec_module(cls.goodinfo_joint_run)
            # 使用 staticmethod 封裝，避免類別屬性轉 instance method 時引發 self 參數錯位
            cls.inspect_ast_for_chart_script = staticmethod(cls.goodinfo_joint_run.inspect_ast_for_chart_script)
            mock_sub.assert_not_called()

    def test_positive_case_get(self):
        code = '''
import os
script = os.environ.get("CHART_SCRIPT") or "chart_draw.py"
print("OK")
'''
        ok, msg = self.inspect_ast_for_chart_script(code)
        self.assertTrue(ok, f"應通過正向 get 案例: {msg}")

    def test_positive_case_subscript(self):
        code = '''
import os
script = os.environ["CHART_SCRIPT"]
'''
        ok, msg = self.inspect_ast_for_chart_script(code)
        self.assertTrue(ok, f"應通過正向 subscript 案例: {msg}")

    def test_missing_capability(self):
        code = '''
import os
print("Hello World")
'''
        ok, msg = self.inspect_ast_for_chart_script(code)
        self.assertFalse(ok, "無能力案例應判定失敗")

    def test_pure_comment_case(self):
        code = '''
import os
# script = os.environ.get("CHART_SCRIPT")
"""
os.environ["CHART_SCRIPT"] in docstring
"""
print("Comment test")
'''
        ok, msg = self.inspect_ast_for_chart_script(code)
        self.assertFalse(ok, "純註解/Docstring 案例應判定失敗")

    def test_fake_environ_case(self):
        code = '''
fake = type('Fake', (), {'environ': {'CHART_SCRIPT': 'hack'}})
script = fake.environ.get("CHART_SCRIPT")
'''
        ok, msg = self.inspect_ast_for_chart_script(code)
        self.assertFalse(ok, "fake.environ 假陽性案例應判定失敗")

    def test_syntax_error_case(self):
        code = '''
def invalid_python_syntax(
'''
        ok, msg = self.inspect_ast_for_chart_script(code)
        self.assertFalse(ok, "語法錯誤案例應判定失敗")

    def test_import_no_side_effects(self):
        """驗證動態載入 run.py 模組時完全無 subprocess.run 副作用 (0 次呼叫)"""
        with patch("subprocess.run") as mock_sub:
            s = importlib.util.spec_from_file_location("goodinfo_joint_run_isolated", self.RUN_PY_PATH)
            m = importlib.util.module_from_spec(s)
            s.loader.exec_module(m)
            mock_sub.assert_not_called()

    @patch("subprocess.run")
    def test_main_smoke_test(self, mock_sub):
        """Smoke Test: 驗證 main() 控制流、步驟調用次數與 Temp 檔案隔離"""
        import tempfile, os
        mock_sub.return_value.returncode = 0
        mock_sub.return_value.stdout = "OK"

        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.dict(os.environ, {"TEMP": tmpdir}):
                with patch.object(self.goodinfo_joint_run, "check_scraper_capability") as mock_check_cap:
                    try:
                        self.goodinfo_joint_run.main()
                    except SystemExit as e:
                        self.assertEqual(e.code, 0)
                    self.assertTrue(mock_check_cap.called, "main() 應正常調用 check_scraper_capability")
                    self.assertGreaterEqual(mock_sub.call_count, 2, "應至少調用 2 次 subprocess.run 執行 pipeline 步驟")

    @patch("subprocess.run")
    def test_main_step_failure_exits_nonzero(self, mock_sub):
        """驗證當步驟 returncode != 0 時，main() 精確引發 SystemExit(1) 中止"""
        import tempfile, os
        mock_sub.return_value.returncode = 1
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch.dict(os.environ, {"TEMP": tmpdir}):
                with patch.object(self.goodinfo_joint_run, "check_scraper_capability"):
                    with self.assertRaises(SystemExit) as cm:
                        self.goodinfo_joint_run.main()
                    self.assertEqual(cm.exception.code, 1)

if __name__ == "__main__":
    unittest.main()
