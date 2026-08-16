"""
run.py - goodinfo-joint 主流程
外資投信同買分析：爬外資佔股本比 → JOIN投信資料 → 輸出報表+K線圖+Discord
"""
import sys, os, subprocess, site
from pathlib import Path

PYTHON = sys.executable
SKILL_DIR = Path(__file__).resolve().parent

def resolve_scraper_dir():
    if "SCRAPER_DIR" in os.environ and os.path.isdir(os.environ["SCRAPER_DIR"]):
        return Path(os.environ["SCRAPER_DIR"]).resolve()
    for parent in [SKILL_DIR, *SKILL_DIR.parents]:
        cand = parent / "goodinfo-scraper"
        if cand.is_dir():
            return cand.resolve()
        cand_sub = parent.parent / "goodinfo-scraper"
        if cand_sub.is_dir():
            return cand_sub.resolve()
    fallback = SKILL_DIR.parent.parent.parent / "goodinfo-scraper"
    return fallback.resolve()

SCRAPER = resolve_scraper_dir()

import ast

def is_os_environ_node(val_node):
    """驗證 AST 節點是否為標準的 Name(id='os') -> Attribute(attr='environ')"""
    if isinstance(val_node, ast.Attribute) and val_node.attr == 'environ':
        if isinstance(val_node.value, ast.Name) and val_node.value.id == 'os':
            return True
    return False

def inspect_ast_for_chart_script(code_text, filename="<string>"):
    """使用 Python ast 模組，精確驗證語法樹中是否含有讀取 os.environ['CHART_SCRIPT'] 的程式碼節點"""
    try:
        tree = ast.parse(code_text, filename=filename)
    except Exception as e:
        return False, f"AST 解析失敗: {e}"

    for node in ast.walk(tree):
        # 1. 匹配 os.environ.get("CHART_SCRIPT")
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Attribute) and func.attr == 'get':
                if is_os_environ_node(func.value):
                    if node.args and getattr(node.args[0], 'value', None) == 'CHART_SCRIPT':
                        return True, "Found os.environ.get('CHART_SCRIPT')"
        # 2. 匹配 os.environ["CHART_SCRIPT"]
        elif isinstance(node, ast.Subscript):
            if is_os_environ_node(node.value):
                slice_val = getattr(node.slice, 'value', None)
                if slice_val == 'CHART_SCRIPT':
                    return True, "Found os.environ['CHART_SCRIPT']"
    return False, "未發現讀取 os.environ['CHART_SCRIPT'] 之程式碼節點"

def check_scraper_capability():
    """雙檔案 (recommend.py, trust_trend.py) AST 語法樹能力檢查"""
    for file_name in ["recommend.py", "trust_trend.py"]:
        target_py = SCRAPER / file_name
        if not target_py.exists():
            print(f"❌ 找不到 goodinfo-scraper 程式檔：{target_py}")
            sys.exit(1)
        code = target_py.read_text(encoding="utf-8", errors="ignore")
        ok, msg = inspect_ast_for_chart_script(code, filename=str(target_py))
        if not ok:
            print(f"❌ AST 檢驗失敗 ({file_name})：{msg}，請更新至 Commit @9a6ffb9 或更新版本！")
            sys.exit(1)
    print("✅ goodinfo-scraper 雙檔案 (recommend.py, trust_trend.py) AST 語法樹級別能力檢查通過")

def main():
    check_scraper_capability()

    # 動態補充 Python site-packages
    user_site = site.getusersitepackages()
    if user_site and os.path.isdir(user_site) and user_site not in sys.path:
        sys.path.insert(0, user_site)

    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    env["SCRAPER_DIR"] = str(SCRAPER)

    token = get_secret("DISCORD_BOT_TOKEN")
    thread_id = get_secret("DISCORD_THREAD_ID")
    if token:     env["DISCORD_BOT_TOKEN"] = token
    if thread_id: env["DISCORD_CHANNEL_ID"] = thread_id

    # Step 1: 爬外資佔股本比
    run("1/2", SKILL_DIR / "scrape_foreign_pct.py", cwd=SKILL_DIR, env=env)

    # Step 2: 分析 + 輸出 + Discord
    run("2/2", SKILL_DIR / "analyze_joint.py", cwd=SKILL_DIR, env=env)

    print("Done.")

if __name__ == "__main__":
    main()
