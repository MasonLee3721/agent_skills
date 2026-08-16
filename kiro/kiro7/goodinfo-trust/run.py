"""
run.py - 跨平台台股投信買超分析 pipeline 主流程
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
    # 預設探索同級或上一層之 goodinfo-scraper
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
def get_secret(key):
    val = os.environ.get(key)
    if val:
        return val
    for base in [SKILL_DIR, *SKILL_DIR.parents]:
        sm = base / "passkey" / "secrets_manager.py"
        if sm.exists():
            try:
                r = subprocess.run([PYTHON, str(sm), "get", key], capture_output=True, text=True)
                if r.returncode == 0 and r.stdout.strip():
                    return r.stdout.strip()
            except Exception:
                pass
    return ""

def run(step, script, cwd=SCRAPER, env=None):
    print(f"[{step}] {script}...")
    r = subprocess.run([PYTHON, script], cwd=str(cwd), env=env, capture_output=False)
    if r.returncode != 0:
        print(f"❌ FAILED at step {step}")
        sys.exit(1)

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
    if token:
        env["DISCORD_BOT_TOKEN"] = token
    if thread_id:
        env["DISCORD_CHANNEL_ID"] = thread_id

    # Step 1-5
    for step, script in [
        ("1/5", "scrape_goodinfo.py"),
        ("2/5", "scrape_foreign.py"),
        ("3/5", "analyze.py"),
        ("4/5", "trust_trend.py"),
        ("5/5", "screen.py"),
    ]:
        run(step, script, cwd=SCRAPER, env=env)

    # Step 6: recommend（零檔案覆蓋，經由環境變數傳遞自訂 K線圖繪製腳本）
    print("[recommend] recommend + chart...")
    chart_win = str(SKILL_DIR / "chart_draw_win.py")
    env["CHART_SCRIPT"] = chart_win

    temp_dir = os.environ.get("TEMP", str(SCRAPER))
    recommend_out = os.path.join(temp_dir, "recommend_out.txt")
    with open(recommend_out, "w", encoding="utf-8") as f:
        res = subprocess.run([PYTHON, "recommend.py"], cwd=str(SCRAPER), env=env, stdout=f, stderr=f)
        if res.returncode != 0:
            print(f"❌ FAILED at recommend.py (exit code {res.returncode})")
            sys.exit(1)

    # 印出推薦結果
    import io
    if hasattr(sys.stdout, 'buffer'):
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    if os.path.exists(recommend_out):
        print(open(recommend_out, encoding="utf-8", errors="ignore").read())

    # 傳送 Discord
    res_discord = subprocess.run([PYTHON, str(SKILL_DIR / "send_recommend.py"),
                                  recommend_out, env.get("DISCORD_CHANNEL_ID", "")],
                                 env=env, capture_output=False)
    if res_discord.returncode != 0:
        print(f"❌ FAILED at send_recommend.py (exit code {res_discord.returncode})")
        sys.exit(1)

    print(f"Done. Charts: {SCRAPER / 'charts'}")

if __name__ == "__main__":
    main()

