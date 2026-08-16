"""
patch_for_windows.py - 修正 goodinfo-scraper 腳本的 Linux 相依問題
執行一次即可，會直接修改 trust_trend.py
"""
import os
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

# ── 修正 trust_trend.py：uv -> python ──────────────────────────
tt = SCRAPER / "trust_trend.py"
content = tt.read_text(encoding="utf-8")

old = '''    uv = os.path.expanduser("~/.local/bin/uv")
    chart_script = str(Path(__file__).parent / "chart_draw.py")

    print(f"\\n📊 產生 K 線圖中...")
    for i, (_, r) in enumerate(df.head(5).iterrows()):
        if i > 0:
            import time; time.sleep(15)  # 避免 yfinance rate limit
        code = str(r["代號"])
        subprocess.run(
            [uv, "run", "--with", "pandas", "--with", "requests", "--with",
             "mplfinance", "--with", "matplotlib", "--with", "yfinance",
             "python3", chart_script, code],
            capture_output=True
        )'''

new = '''    import sys
    chart_script = str(Path(__file__).parent / "chart_draw.py")

    print(f"\\n📊 產生 K 線圖中...")
    for i, (_, r) in enumerate(df.head(5).iterrows()):
        if i > 0:
            import time; time.sleep(15)  # 避免 yfinance rate limit
        code = str(r["代號"])
        subprocess.run(
            [sys.executable, chart_script, code],
            capture_output=True
        )'''

if old in content:
    tt.write_text(content.replace(old, new), encoding="utf-8")
    print("OK: trust_trend.py patched")
else:
    print("SKIP: trust_trend.py already patched or content mismatch")
