"""
send_recommend.py - 讀取 recommend 輸出 log，傳送推薦清單文字到 Discord
用法：python send_recommend.py <log_file> <channel_id>
"""
import sys, os

# 確保 user site-packages 在 path
import site
for p in [site.getusersitepackages(),
          os.path.join(os.environ.get("APPDATA",""), "Python",
                       f"Python{sys.version_info.major}{sys.version_info.minor}",
                       "site-packages")]:
    if p and os.path.isdir(p) and p not in sys.path:
        sys.path.insert(0, p)

from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent

def resolve_scraper_dir():
    if "SCRAPER_DIR" in os.environ and os.path.isdir(os.environ["SCRAPER_DIR"]):
        return Path(os.environ["SCRAPER_DIR"]).resolve()
    for parent in [SKILL_DIR, *SKILL_DIR.parents]:
        cand = parent / "goodinfo-scraper"
        if cand.is_dir():
            return cand
        cand_sub = parent.parent / "goodinfo-scraper"
        if cand_sub.is_dir():
            return cand_sub
    default_dir = Path(r"C:\openab\goodinfo-scraper") if os.name == "nt" else Path("/home/agent/goodinfo-scraper")
    return default_dir

SCRAPER = resolve_scraper_dir()
if str(SCRAPER) not in sys.path:
    sys.path.insert(0, str(SCRAPER))
if SCRAPER.is_dir():
    os.chdir(str(SCRAPER))

from discord_send import send_text

log_file = sys.argv[1] if len(sys.argv) > 1 else None
channel_id = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("DISCORD_CHANNEL_ID", "")

if not log_file or not os.path.exists(log_file):
    print("log file not found")
    sys.exit(1)

txt = open(log_file, encoding="utf-8", errors="ignore").read()

# 只取推薦清單部分（從 === 開始）
start = txt.find("===")
msg = txt[start:].strip() if start >= 0 else txt.strip()

# Discord 單則上限 2000 字，分段傳送
for i in range(0, len(msg), 1900):
    send_text(channel_id, msg[i:i+1900])
    print(f"sent {min(i+1900, len(msg))}/{len(msg)} chars")
