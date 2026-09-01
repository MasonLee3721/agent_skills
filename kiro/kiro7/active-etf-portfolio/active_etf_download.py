"""
ETF 基金投資組合下載腳本
每日下載 ezmoney 的 ETF 持股 Excel，並與前日比對買賣變化
用法: python download_etf.py
"""
import os
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
from datetime import datetime
from pathlib import Path

FUND_CODE = "49YTW"  # 台股代號：00981A（統一臺灣成長主動ETF），ezmoney 內部代碼為 49YTW
URL = f"https://www.ezmoney.com.tw/ETF/Fund/Info?fundCode={FUND_CODE}"
SAVE_DIR = Path(__file__).parent / "data"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"


def download_excel() -> Path:
    SAVE_DIR.mkdir(parents=True, exist_ok=True)
    today = datetime.now().strftime("%Y%m%d")
    dest = SAVE_DIR / f"active_etf_{FUND_CODE}_{today}.xlsx"

    if dest.exists():
        print(f"[已存在] {dest.name}，跳過下載")
        return dest

    try:
        import requests
        import urllib3
        urllib3.disable_warnings()

        print(f"[開啟 HTTP 請求下載] {URL}")
        s = requests.Session()
        s.headers.update({"User-Agent": UA})
        s.get("https://www.ezmoney.com.tw/", verify=False, timeout=15)
        s.get(URL, verify=False, timeout=15)

        dl_url = f"https://www.ezmoney.com.tw/ETF/Fund/AssetExcelNPOI?fundCode={FUND_CODE}"
        r = s.get(dl_url, verify=False, timeout=20)
        if r.status_code == 200 and len(r.content) > 1000:
            dest.write_bytes(r.content)
            print(f"[下載完成] {dest}")
            return dest
    except Exception as exc:
        print(f"[HTTP 下載失敗，嘗試 Playwright 降級方案] {exc}")

    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            ctx = browser.new_context(
                viewport={"width": 1280, "height": 900},
                user_agent=UA,
                accept_downloads=True
            )
            page = ctx.new_page()
            page.goto(URL, wait_until="networkidle", timeout=30000)
            tab = page.locator("a", has_text="基金投資組合")
            if tab.count() > 0:
                tab.first.click()
                page.wait_for_timeout(2000)
            expand = page.locator("text=展開全部")
            if expand.count() > 0:
                expand.first.click()
                page.wait_for_timeout(1500)
            page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
            page.wait_for_timeout(1000)
            xlsx_btn = page.locator("text=匯出XLSX檔")
            with page.expect_download(timeout=30000) as dl_info:
                xlsx_btn.first.click()
            download = dl_info.value
            download.save_as(dest)
            browser.close()
            print(f"[下載完成] {dest}")
            return dest
    except Exception as exc:
        raise RuntimeError(f"Download 00981A active ETF failed: {exc}")


def compare_with_yesterday(today_file: Path):
    import openpyxl

    files = sorted(SAVE_DIR.glob(f"active_etf_{FUND_CODE}_*.xlsx"))
    if len(files) < 2:
        print("\n[比對] 無前日資料，跳過比對")
        return

    yesterday_file = files[-2]
    print(f"\n[比對] {yesterday_file.name}  →  {today_file.name}")

    def load(path):
        wb = openpyxl.load_workbook(path)
        ws = wb.active
        rows = list(ws.iter_rows(values_only=True))
        # 找含「股票代號」的標題列
        header_idx = next(
            (i for i, r in enumerate(rows) if r and any("股票代號" in str(c) for c in r if c)),
            None
        )
        if header_idx is None:
            return {}, {}
        shares_map, name_map = {}, {}
        for row in rows[header_idx + 1:]:
            if not row or not row[0]:
                continue
            code = str(row[0]).strip()
            if not code or code == "None":
                continue
            name_map[code] = str(row[1]).strip() if row[1] else ""
            try:
                shares_map[code] = int(str(row[2]).replace(",", "").split(".")[0])
            except Exception:
                shares_map[code] = 0
        return shares_map, name_map

    prev_shares, _ = load(yesterday_file)
    curr_shares, curr_names = load(today_file)
    # 合併名稱（出清的股票名稱從前日取）
    _, prev_names = load(yesterday_file)
    all_names = {**prev_names, **curr_names}

    all_codes = set(prev_shares) | set(curr_shares)

    new_in, out, buy, sell = [], [], [], []
    for code in all_codes:
        p, c = prev_shares.get(code, 0), curr_shares.get(code, 0)
        if code not in prev_shares:
            new_in.append((code, c))
        elif code not in curr_shares:
            out.append((code, p))
        elif c > p:
            buy.append((code, c - p))
        elif c < p:
            sell.append((code, p - c))

    def label(code):
        name = all_names.get(code, "")
        return f"{code} {name}" if name else code

    print("\n========== 今日異動 ==========")
    if new_in:
        print("[+] 新買進：")
        for code, s in new_in:
            print(f"   {label(code)}  +{s:,} 股")
    if buy:
        print("[^] 加碼：")
        for code, s in sorted(buy, key=lambda x: -x[1]):
            print(f"   {label(code)}  +{s:,} 股")
    if sell:
        print("[v] 減碼：")
        for code, s in sorted(sell, key=lambda x: -x[1]):
            print(f"   {label(code)}  -{s:,} 股")
    if out:
        print("[-] 出清：")
        for code, s in out:
            print(f"   {label(code)}  -{s:,} 股")
    if not any([new_in, buy, sell, out]):
        print("  無異動")
    print("==============================")


if __name__ == "__main__":
    try:
        import openpyxl
    except ImportError:
        os.system("pip install openpyxl -q")

    today_file = download_excel()
    compare_with_yesterday(today_file)
