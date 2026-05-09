"""
自繪 K 線圖（Windows 版）：從證交所/櫃買抓資料，用 mplfinance 畫出含均線、KD、MACD 的技術圖
用法：python chart_draw_win.py 6706
"""
import sys, warnings

# 確保 user site-packages 在 path 中（Windows subprocess 不繼承 PYTHONPATH）
import site
_user_sp = site.getusersitepackages()
if _user_sp not in sys.path:
    sys.path.insert(0, _user_sp)
# AppData\Roaming 版本
import os as _os
_roaming_sp = _os.path.join(_os.environ.get("APPDATA",""), "Python", f"Python{sys.version_info.major}{sys.version_info.minor}", "site-packages")
if _os.path.isdir(_roaming_sp) and _roaming_sp not in sys.path:
    sys.path.insert(0, _roaming_sp)

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import matplotlib.dates as mdates
from matplotlib.patches import Rectangle
from pathlib import Path

warnings.filterwarnings('ignore')

# Windows 微軟正黑體
plt.rcParams['font.family'] = ['Microsoft JhengHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

STOCK_ID = sys.argv[1] if len(sys.argv) > 1 else '2330'
# 當此檔被 copy 到 goodinfo-scraper/ 後，__file__ 的 parent 就是 goodinfo-scraper/
OUT_DIR = Path(__file__).parent / 'charts'
OUT_DIR.mkdir(exist_ok=True)


def _is_otc(stock_id: str) -> bool:
    """上櫃判斷：代號開頭 4~9 且非特定上市例外"""
    try:
        n = int(stock_id)
        return 4000 <= n <= 9999
    except ValueError:
        return False  # 英文代號（ETF 等）預設上市

def _yf_download(ticker: str, months: int, max_retries: int = 3):
    """yfinance 下載，遇 rate limit 自動等待重試"""
    import yfinance as yf
    import random
    for attempt in range(max_retries):
        try:
            df = yf.download(ticker, period=f'{months}mo',
                             interval='1d', progress=False, auto_adjust=True)
            if df is not None and len(df) >= 20:
                return df
            return None
        except Exception as e:
            msg = str(e).lower()
            if 'rate' in msg or '429' in msg or 'too many' in msg:
                wait = random.uniform(5, 15)  # 5~15 秒隨機等待
                print(f"  yfinance rate limit，等待 {wait:.1f}s...")
                import time; time.sleep(wait)
            else:
                return None
    return None

def get_kline(stock_id, months=5):
    # 依代號決定先試哪個市場
    if _is_otc(stock_id):
        order = ['.TWO', '.TW']
    else:
        order = ['.TW', '.TWO']

    for suffix in order:
        df = _yf_download(f'{stock_id}{suffix}', months)
        if df is not None:
            df = df[['Open', 'High', 'Low', 'Close', 'Volume']].copy()
            df.columns = ['Open', 'High', 'Low', 'Close', 'Volume']
            df['Volume'] = (df['Volume'] // 1000).astype(int)
            df.index = pd.to_datetime(df.index.date)
            df.index.name = 'Date'
            return df
    return None


def calc_rsi(close, n=14):
    delta = close.diff()
    gain = delta.clip(lower=0).rolling(n).mean()
    loss = (-delta.clip(upper=0)).rolling(n).mean()
    rs = gain / loss
    return 100 - 100 / (1 + rs)


def calc_macd(close, fast=12, slow=26, signal=9):
    ema_fast = close.ewm(span=fast, adjust=False).mean()
    ema_slow = close.ewm(span=slow, adjust=False).mean()
    dif = ema_fast - ema_slow
    dea = dif.ewm(span=signal, adjust=False).mean()
    hist = (dif - dea) * 2
    return dif, dea, hist


def calc_kd(high, low, close, n=9):
    low_n = low.rolling(n).min()
    high_n = high.rolling(n).max()
    rsv = (close - low_n) / (high_n - low_n) * 100
    K = rsv.ewm(com=2, adjust=False).mean()
    D = K.ewm(com=2, adjust=False).mean()
    return K, D


def draw_chart(stock_id):
    print(f"抓取 {stock_id} 資料中...")
    df = get_kline(stock_id)
    if df is None or len(df) < 30:
        print(f"資料不足，無法畫圖")
        return None

    df = df.tail(90).copy()

    rsi = calc_rsi(df['Close'])
    dif, dea, hist = calc_macd(df['Close'])
    K, D = calc_kd(df['High'], df['Low'], df['Close'])
    ma5  = df['Close'].rolling(5).mean()
    ma20 = df['Close'].rolling(20).mean()
    ma60 = df['Close'].rolling(60).mean()

    fig, axes = plt.subplots(5, 1, figsize=(14, 12),
                             gridspec_kw={'height_ratios': [4, 1, 1.2, 1.2, 1.5]},
                             sharex=True)
    fig.subplots_adjust(hspace=0.05)
    ax_k, ax_vol, ax_rsi, ax_kd, ax_macd = axes

    dates = mdates.date2num(df.index.to_pydatetime())
    w = 0.6
    for i, (dt, row) in enumerate(df.iterrows()):
        color = '#ef233c' if row['Close'] >= row['Open'] else '#4cc9f0'
        ax_k.add_patch(Rectangle(
            (dates[i] - w/2, min(row['Open'], row['Close'])),
            w, abs(row['Close'] - row['Open']),
            color=color, zorder=3
        ))
        ax_k.plot([dates[i], dates[i]], [row['Low'], row['High']], color=color, lw=0.8, zorder=2)

    ax_k.plot(dates, ma5,  color='#ff6b6b', lw=1.2, label='MA5')
    ax_k.plot(dates, ma20, color='#ffd93d', lw=1.2, label='MA20')
    ax_k.plot(dates, ma60, color='#00cfff', lw=1.2, label='MA60')
    ax_k.set_ylabel('Price', fontsize=9)
    ax_k.legend(loc='upper left', fontsize=8)
    ax_k.set_title(f'股票 {stock_id}  日K線  (MA5/20/60 · RSI · KD · MACD)', fontsize=12, color='#dddddd')
    ax_k.xaxis_date()

    for i, (dt, row) in enumerate(df.iterrows()):
        color = '#ef233c' if row['Close'] >= row['Open'] else '#4cc9f0'
        ax_vol.bar(dates[i], row['Volume'], width=w, color=color, alpha=0.8)
    ax_vol.set_ylabel('量(張)', fontsize=9)

    ax_rsi.plot(dates, rsi, color='#845ec2', lw=1.2)
    ax_rsi.axhline(70, color='gray', ls='--', lw=0.8)
    ax_rsi.axhline(30, color='gray', ls='--', lw=0.8)
    ax_rsi.set_ylim(0, 100)
    ax_rsi.set_yticks([30, 50, 70])
    ax_rsi.set_ylabel('RSI', fontsize=9)

    ax_kd.plot(dates, K, color='#f9844a', lw=1.2, label='K')
    ax_kd.plot(dates, D, color='#4d908e', lw=1.2, label='D')
    ax_kd.axhline(80, color='gray', ls='--', lw=0.8)
    ax_kd.axhline(20, color='gray', ls='--', lw=0.8)
    ax_kd.set_ylim(0, 100)
    ax_kd.set_yticks([20, 50, 80])
    ax_kd.set_ylabel('KD', fontsize=9)
    ax_kd.legend(loc='upper left', fontsize=8)

    ax_macd.plot(dates, dif, color='#f9844a', lw=1.2, label='DIF')
    ax_macd.plot(dates, dea, color='#4d908e', lw=1.2, label='DEA')
    bar_colors = ['#ef233c' if v >= 0 else '#4cc9f0' for v in hist.fillna(0)]
    ax_macd.bar(dates, hist, width=w, color=bar_colors, alpha=0.8)
    ax_macd.axhline(0, color='gray', lw=0.8)
    ax_macd.set_ylabel('MACD', fontsize=9)
    ax_macd.legend(loc='upper left', fontsize=8)

    ax_macd.xaxis.set_major_formatter(mdates.DateFormatter('%m/%d'))
    ax_macd.xaxis.set_major_locator(mdates.WeekdayLocator(byweekday=0, interval=2))
    plt.setp(ax_macd.xaxis.get_majorticklabels(), rotation=45, ha='right', fontsize=8)

    for ax in axes:
        ax.set_facecolor('#1a1a2e')
        ax.tick_params(colors='#aaa', labelsize=8)
        for spine in ax.spines.values():
            spine.set_edgecolor('#333')
    fig.patch.set_facecolor('#0f0f1a')

    out_path = str(OUT_DIR / f'{stock_id}.png')
    plt.savefig(out_path, dpi=120, bbox_inches='tight', facecolor=fig.get_facecolor())
    plt.close()
    print(f"圖表已儲存：{out_path}")
    return out_path


if __name__ == '__main__':
    draw_chart(STOCK_ID)
