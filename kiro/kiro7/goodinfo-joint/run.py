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
