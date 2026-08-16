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

def check_scraper_capability():
    recommend_py = SCRAPER / "recommend.py"
    if not recommend_py.exists():
        print(f"❌ 找不到 goodinfo-scraper 程式檔：{recommend_py}")
        sys.exit(1)

    code = recommend_py.read_text(encoding="utf-8", errors="ignore")
    try:
        tree = ast.parse(code, filename=str(recommend_py))
    except Exception as e:
        print(f"❌ 解析 {recommend_py} AST 抽象語法樹失敗：{e}")
        sys.exit(1)

    found_ast_read = False
    for node in ast.walk(tree):
        # 匹配 Call 節點: os.environ.get("CHART_SCRIPT")
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Attribute) and func.attr == 'get':
                val = func.value
                if isinstance(val, ast.Attribute) and val.attr == 'environ':
                    if node.args and getattr(node.args[0], 'value', None) == 'CHART_SCRIPT':
                        found_ast_read = True; break
        # 匹配 Subscript 節點: os.environ["CHART_SCRIPT"]
        elif isinstance(node, ast.Subscript):
            val = node.value
            if isinstance(val, ast.Attribute) and val.attr == 'environ':
                slice_val = getattr(node.slice, 'value', None)
                if slice_val == 'CHART_SCRIPT':
                    found_ast_read = True; break

    if not found_ast_read:
        print(f"❌ AST 檢驗失敗：goodinfo-scraper ({SCRAPER}) 語法樹中未發現讀取 os.environ['CHART_SCRIPT'] 之程式碼節點！")
        sys.exit(1)
    print("✅ goodinfo-scraper AST 抽象語法樹級別能力檢查通過")

check_scraper_capability()

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

def run(label, script, cwd=SCRAPER, env=None):
    print(f"[{label}] {os.path.basename(script)}...")
    r = subprocess.run([PYTHON, str(script)], cwd=str(cwd), env=env)
    if r.returncode != 0:
        print(f"FAILED at {label}")
        sys.exit(1)

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
