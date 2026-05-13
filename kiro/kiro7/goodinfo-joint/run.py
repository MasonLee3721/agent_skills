"""
run.py - goodinfo-joint 主流程
外資投信同買分析：爬外資佔股本比 → JOIN投信資料 → 輸出報表+K線圖+Discord
"""
import sys, os, subprocess

PYTHON = sys.executable
SKILL_DIR = os.path.dirname(os.path.abspath(__file__))
SCRAPER = r"C:\openab\goodinfo-scraper"

def get_secret(key):
    try:
        r = subprocess.run(
            [PYTHON, r"C:\openab\passkey\secrets_manager.py", "get", key],
            capture_output=True, text=True
        )
        return r.stdout.strip()
    except:
        return ""

def run(label, script, cwd=SCRAPER, env=None):
    print(f"[{label}] {os.path.basename(script)}...")
    r = subprocess.run([PYTHON, script], cwd=cwd, env=env)
    if r.returncode != 0:
        print(f"FAILED at {label}")
        sys.exit(1)

env = os.environ.copy()
env["PYTHONIOENCODING"] = "utf-8"
env["PYTHONPATH"] = (
    r"C:\Users\swalz\AppData\Roaming\Python\Python314\site-packages;"
    r"C:\Users\swalz\Python\Python314\site-packages"
)
token = get_secret("DISCORD_BOT_TOKEN")
thread_id = get_secret("DISCORD_THREAD_ID")
if token:     env["DISCORD_BOT_TOKEN"] = token
if thread_id: env["DISCORD_CHANNEL_ID"] = thread_id

# Step 1: 爬外資佔股本比
run("1/2", os.path.join(SKILL_DIR, "scrape_foreign_pct.py"), cwd=SKILL_DIR, env=env)

# Step 2: 分析 + 輸出 + Discord
run("2/2", os.path.join(SKILL_DIR, "analyze_joint.py"), cwd=SKILL_DIR, env=env)

print("Done.")
