"""
外資投信同買分析
條件：投信佔股本比 > 0.1% 且 外資佔股本比 > 0.6%
輸出：前10檔（按外資%排序），前5檔附K線圖傳Discord
執行：python analyze_joint.py
"""
import sys, io, os, glob
if hasattr(sys.stdout, 'buffer') and sys.stdout.encoding.lower() != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

import pandas as pd
import subprocess
from pathlib import Path

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

SCRAPER = str(resolve_scraper_dir())
TRUST_PCT_COL = "當日買賣超佔發行張數"
FOREIGN_PCT_COL = "當日買賣超佔發行張數"
MIN_TRUST = 0.1
MIN_FOREIGN = 0.6
TOP_N = 10
CHART_N = 5

if SCRAPER not in sys.path:
    sys.path.insert(0, SCRAPER)
from discord_send import send_text, send_image

def load_latest(folder):
    files = sorted(glob.glob(os.path.join(SCRAPER, folder, "*.csv")))
    if not files:
        return None, None
    df = pd.read_csv(files[-1], dtype=str)
    date_str = os.path.basename(files[-1]).replace(".csv", "")
    return df, date_str

def main():
    # 載入投信資料
    trust_df, trust_date = load_latest("data")
    if trust_df is None:
        print("找不到投信資料，請先執行 scrape_goodinfo.py"); return

    # 載入外資佔股本比資料
    foreign_df, foreign_date = load_latest("data_foreign_pct")
    if foreign_df is None:
        print("找不到外資佔股本比資料，請先執行 scrape_foreign_pct.py"); return

    # 統一欄位，取需要的欄
    trust_df[TRUST_PCT_COL] = pd.to_numeric(trust_df[TRUST_PCT_COL], errors="coerce")
    # 外資那張表欄位名稱可能不同，找「當日」相關欄
    foreign_pct_col = next(
        (c for c in foreign_df.columns if "當日" in c and "買賣超" in c), None
    )
    if not foreign_pct_col:
        # fallback：取第一個含%或買賣超的數值欄
        foreign_pct_col = next(
            (c for c in foreign_df.columns if "買賣超" in c), foreign_df.columns[7]
        )
    foreign_df[foreign_pct_col] = pd.to_numeric(foreign_df[foreign_pct_col], errors="coerce")

    # 篩選
    trust_ok = trust_df[trust_df[TRUST_PCT_COL] > MIN_TRUST][["代號", "名稱", TRUST_PCT_COL]].copy()
    trust_ok.rename(columns={TRUST_PCT_COL: "投信%"}, inplace=True)

    foreign_ok = foreign_df[foreign_df[foreign_pct_col] > MIN_FOREIGN][["代號", "名稱", foreign_pct_col]].copy()
    foreign_ok.rename(columns={foreign_pct_col: "外資%", "名稱": "名稱_外"}, inplace=True)
    foreign_ok["代號"] = foreign_ok["代號"].str.strip()
    trust_ok["代號"] = trust_ok["代號"].str.strip()

    # JOIN
    merged = pd.merge(trust_ok, foreign_ok[["代號", "外資%"]], on="代號", how="inner")
    if merged.empty:
        print(f"[{trust_date}] 無符合條件的股票（投信>{MIN_TRUST}% 且 外資>{MIN_FOREIGN}%）"); return

    merged = merged.sort_values("外資%", ascending=False).head(TOP_N).reset_index(drop=True)

    # 輸出報表
    date_label = trust_date.replace("-", "/")[5:]  # MM/DD
    lines = [f"📊 投外本比入榜（投信外資同買）{date_label}"]
    lines.append(f"條件：投信>{MIN_TRUST}% 且 外資>{MIN_FOREIGN}%，共{len(merged)}檔\n")
    for _, r in merged.iterrows():
        lines.append(f"{r['代號']}{r['名稱']}")
        lines.append(f"投{r['投信%']:.2f}、外{r['外資%']:.2f}")
    report = "\n".join(lines)
    print(report)

    # 傳 Discord 文字
    channel_id = os.environ.get("DISCORD_CHANNEL_ID", "1499988458825977978")
    send_text(channel_id, report)

    # 前5檔畫K線圖並傳Discord
    chart_script = str(Path(SCRAPER) / "chart_draw.py")
    print(f"\n📊 產生 K 線圖中（前{CHART_N}檔）...")
    for i, (_, r) in enumerate(merged.head(CHART_N).iterrows()):
        code = str(r["代號"])
        subprocess.run([sys.executable, chart_script, code],
                       capture_output=True, cwd=SCRAPER)
        chart_path = Path(SCRAPER) / "charts" / f"{code}.png"
        if chart_path.exists():
            send_image(channel_id, str(chart_path),
                       f"📊 【外資投信同買 #{i+1}】{code} {r['名稱']}  投{r['投信%']:.2f}% 外{r['外資%']:.2f}%")
        else:
            print(f"  ⚠️  {code} 圖表產生失敗")

if __name__ == "__main__":
    main()
