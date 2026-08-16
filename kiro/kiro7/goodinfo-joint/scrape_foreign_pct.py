"""
爬取 Goodinfo 外資買超佔發行張數排行，存成每日 CSV
執行：python scrape_foreign_pct.py
"""
import requests, time, csv, os
from datetime import date
from pathlib import Path
from bs4 import BeautifulSoup

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

REPO_DIR = str(resolve_scraper_dir())
FOLDER = "data_foreign_pct"

API = (
    "https://goodinfo.tw/tw2/StockList.asp?STEP=DATA"
    "&MARKET_CAT=%E7%86%B1%E9%96%80%E6%8E%92%E8%A1%8C"
    "&INDUSTRY_CAT=%E5%A4%96%E8%B3%87%E8%B2%B7%E8%B6%85%E4%BD%94%E7%99%BC%E8%A1%8C%E5%BC%B5%E6%95%B8"
    "+%E2%80%93+%E7%95%B6%E6%97%A5%40%40%E5%A4%96%E8%B3%87%E8%B2%B7%E8%B6%85%E4%BD%94%E7%99%BC%E8%A1%8C%E5%BC%B5%E6%95%B8"
    "%40%40%E5%A4%96%E8%B3%87+%E2%80%93+%E7%95%B6%E6%97%A5"
    "&SHEET=%E6%B3%95%E4%BA%BA%E8%B2%B7%E8%B3%A3%E7%B5%B1%E8%A8%88%5F%E5%A4%96%E8%B3%87"
    "&SHEET2=%E8%B2%B7%E8%B3%A3%E8%B6%85%E4%BD%94%E7%99%BC%E8%A1%8C%E5%BC%B5%E6%95%B8"
    "&RPT_TIME=%E6%9C%80%E6%96%B0%E8%B3%87%E6%96%99"
    "&RANK_RANGE=300"
)
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36",
    "Referer": "https://goodinfo.tw/tw/StockList.asp",
}

def fetch():
    session = requests.Session()
    client_key = os.environ.get("GOODINFO_CLIENT_KEY")
    if client_key:
        session.cookies.set("CLIENT_KEY", client_key, domain="goodinfo.tw", path="/")
    else:
        try:
            session.get("https://goodinfo.tw/tw2/StockList.asp", headers=HEADERS, timeout=15)
        except Exception as e:
            print(f" Goodinfo 建立 session 提示：{e}")

    for attempt in range(3):
        try:
            r = session.get(API, headers=HEADERS, timeout=45)
            r.encoding = "utf-8"
            return r.text
        except Exception as e:
            print(f"第 {attempt+1} 次失敗：{e}，重試中...")
            time.sleep(5)
    raise RuntimeError("連線 goodinfo.tw 失敗，已重試 3 次")

def parse(html):
    soup = BeautifulSoup(html, "html.parser")
    table = soup.find("table", id="tblStockList")
    if not table:
        raise ValueError("找不到資料表，可能被擋了")
    rows = table.find_all("tr")
    headers, data = [], []
    for row in rows:
        ths = row.find_all("th")
        tds = row.find_all("td")
        if ths and not headers:
            headers = [h.get_text(strip=True) for h in ths]
        elif tds:
            data.append([d.get_text(strip=True) for d in tds])
    return headers, data

def save(headers, data):
    os.makedirs(os.path.join(REPO_DIR, FOLDER), exist_ok=True)
    # 從資料找日期欄（格式 MM/DD）
    trade_date = str(date.today().strftime("%m/%d"))
    for cell in data[0]:
        if "/" in cell and len(cell) == 5:
            trade_date = cell
            break
    year = date.today().year
    month, day = trade_date.split("/")
    filename = f"{FOLDER}/{year}-{month}-{day}.csv"
    filepath = os.path.join(REPO_DIR, filename)

    if os.path.exists(filepath):
        print(f"今日資料已存在：{filename}，略過")
        return filepath

    with open(filepath, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(data)
    print(f"已存檔：{filename}（{len(data)} 筆）")
    return filepath

if __name__ == "__main__":
    print("抓取外資佔股本比排行...")
    html = fetch()
    headers, data = parse(html)
    print(f"共 {len(data)} 筆，欄位：{headers[:5]}")
    save(headers, data)
