"""
run.py - 取代 run.bat，用 Python 執行投信買超分析完整流程
"""
import sys, os, subprocess, shutil

PYTHON = sys.executable
SCRAPER = r"C:\openab\goodinfo-scraper"
SKILL_DIR = os.path.dirname(os.path.abspath(__file__))
SECRETS = [PYTHON, r"C:\openab\passkey\secrets_manager.py", "get"]

def get_secret(key):
    try:
        r = subprocess.run(SECRETS + [key], capture_output=True, text=True)
        return r.stdout.strip()
    except:
        return ""

def run(step, script, cwd=SCRAPER, env=None):
    print(f"[{step}] {script}...")
    r = subprocess.run([PYTHON, script], cwd=cwd, env=env,
                       capture_output=False)
    if r.returncode != 0:
        print(f"FAILED at step {step}")
        sys.exit(1)

# 注入環境變數
env = os.environ.copy()
env["PYTHONIOENCODING"] = "utf-8"
env["PYTHONPATH"] = (
    r"C:\Users\swalz\AppData\Roaming\Python\Python314\site-packages;"
    r"C:\Users\swalz\Python\Python314\site-packages"
)
token = get_secret("DISCORD_BOT_TOKEN")
thread_id = get_secret("DISCORD_THREAD_ID")
if token:  env["DISCORD_BOT_TOKEN"] = token
if thread_id: env["DISCORD_CHANNEL_ID"] = thread_id

# Step 0: patch
print("[0/6] patch scripts for Windows...")
subprocess.run([PYTHON, os.path.join(SKILL_DIR, "patch_for_windows.py")],
               capture_output=False)

# Step 1-5
for step, script in [
    ("1/6", "scrape_goodinfo.py"),
    ("2/6", "scrape_foreign.py"),
    ("3/6", "analyze.py"),
    ("4/6", "trust_trend.py"),
    ("5/6", "screen.py"),
]:
    run(step, script, env=env)

# Step 6: recommend（替換 chart_draw.py）
print("[6/6] recommend + chart...")
chart = os.path.join(SCRAPER, "chart_draw.py")
chart_bak = os.path.join(SCRAPER, "chart_draw_bak.py")
chart_win = os.path.join(SKILL_DIR, "chart_draw_win.py")
shutil.copy2(chart, chart_bak)
shutil.copy2(chart_win, chart)

recommend_out = os.path.join(os.environ.get("TEMP", SCRAPER), "recommend_out.txt")
with open(recommend_out, "w", encoding="utf-8") as f:
    subprocess.run([PYTHON, "recommend.py"], cwd=SCRAPER, env=env,
                   stdout=f, stderr=f)

shutil.copy2(chart_bak, chart)
os.remove(chart_bak)

# 印出推薦結果
print(open(recommend_out, encoding="utf-8", errors="ignore").read())

# 傳送 Discord
subprocess.run([PYTHON, os.path.join(SKILL_DIR, "send_recommend.py"),
                recommend_out, env.get("DISCORD_CHANNEL_ID", "")],
               env=env, capture_output=False)

print(f"Done. Charts: {SCRAPER}\\charts\\")
