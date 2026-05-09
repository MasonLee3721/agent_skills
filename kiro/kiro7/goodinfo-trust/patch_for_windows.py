"""
patch_for_windows.py - 修正 goodinfo-scraper 腳本的 Linux 相依問題
執行一次即可，會直接修改 trust_trend.py
"""
import re
from pathlib import Path

SCRAPER = Path(r"C:\openab\goodinfo-scraper")

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
