"""
test_capability.py - AST 執行期能力檢驗單元測試
測試涵蓋 4 大情境：
1. 正向案例 (包含 os.environ.get('CHART_SCRIPT') 或 os.environ['CHART_SCRIPT'])
2. 能力缺失案例 (無 CHART_SCRIPT 邏輯)
3. 純註解/假陽性案例 (僅在註解中或 fake.environ 出現)
4. 語法錯誤案例 (無效 Python 語法)
"""
import unittest
import sys
from pathlib import Path

# 匯入能力檢查核心邏輯
sys.path.insert(0, str(Path(__file__).resolve().parent))
from run import inspect_ast_for_chart_script

class TestScraperCapabilityAST(unittest.TestCase):

    def test_positive_case_get(self):
        code = '''
import os
script = os.environ.get("CHART_SCRIPT") or "chart_draw.py"
print("OK")
'''
        ok, msg = inspect_ast_for_chart_script(code)
        self.assertTrue(ok, f"應通過正向 get 案例: {msg}")

    def test_positive_case_subscript(self):
        code = '''
import os
script = os.environ["CHART_SCRIPT"]
'''
        ok, msg = inspect_ast_for_chart_script(code)
        self.assertTrue(ok, f"應通過正向 subscript 案例: {msg}")

    def test_missing_capability(self):
        code = '''
import os
print("Hello World")
'''
        ok, msg = inspect_ast_for_chart_script(code)
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
        ok, msg = inspect_ast_for_chart_script(code)
        self.assertFalse(ok, "純註解/Docstring 案例應判定失敗")

    def test_fake_environ_case(self):
        code = '''
fake = type('Fake', (), {'environ': {'CHART_SCRIPT': 'hack'}})
script = fake.environ.get("CHART_SCRIPT")
'''
        ok, msg = inspect_ast_for_chart_script(code)
        self.assertFalse(ok, "fake.environ 假陽性案例應判定失敗")

    def test_syntax_error_case(self):
        code = '''
def invalid_python_syntax(
'''
        ok, msg = inspect_ast_for_chart_script(code)
        self.assertFalse(ok, "語法錯誤案例應判定失敗")

if __name__ == "__main__":
    unittest.main()
