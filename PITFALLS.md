# PITFALLS.md — 採坑日記

每次踩坑後記錄在此，讓下次的 AI 不重蹈覆轍。

---

## 2026-05-10

### 1. Windows cp950 編碼問題（emoji / 中文符號）

**症狀：** `UnicodeEncodeError: 'cp950' codec can't encode character`

**根本原因：** Windows 終端機預設 cp950（Big5），無法輸出 emoji 和部分 Unicode 符號（如 `➡️ \u27a1`、`📊 \U0001f4ca`）

**解法（雙保險）：**
1. 每個 Python 腳本開頭加：
```python
import sys, io
if hasattr(sys.stdout, 'buffer') and sys.stdout.encoding.lower() != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
```
2. 執行環境（bat 或呼叫前）加：`set PYTHONIOENCODING=utf-8`

**注意：** 重導向到檔案時（`> out.txt`），stdout 不是 terminal，encoding 行為不同，兩個都要加才保險。

**影響範圍：** `recommend.py`, `analyze.py`, `trust_trend.py`, `screen.py`, `tech_screen.py`, `discord_send.py`

---

### 2. tpex.org.tw OTC API 已失效

**症狀：** HTTP 200 但回傳 HTML 404 頁面，`r.json()` 拋出 `JSONDecodeError`

**根本原因：** `fetch_otc` 使用的舊 endpoint 已下線：
```
https://www.tpex.org.tw/web/stock/aftertrading/daily_trading_info/st43_result.php
```

**解法：** 改用 Yahoo Finance API，上市/上櫃自動判斷：
```python
def fetch_yahoo(code):
    for suffix in [".TW", ".TWO"]:
        url = f"https://query1.finance.yahoo.com/v8/finance/chart/{code}{suffix}?interval=1d&range=6mo"
        r = requests.get(url, timeout=10, headers={"User-Agent": "Mozilla/5.0"})
        d = r.json()
        result = d.get("chart", {}).get("result")
        if result:
            # 解析 timestamps + close + volume
            ...
```

**注意：** 上市用 `.TW`，上櫃用 `.TWO`，先試 `.TW` 失敗再試 `.TWO`。

---

### 3. `except` 靜默吞錯誤導致問題難以追蹤

**症狀：** 某支股票技術面顯示「資料不足」，但實際上是 API 失敗被吞掉

**根本原因：** `fetch_otc` 用裸 `except: return None`，任何錯誤都靜默失敗

**教訓：** 至少要 `except Exception as e: print(f"WARNING: {e}")` 或記 log，不能無聲失敗

---

### 4. Kiro shell 工具無法執行 `.bat` 檔

**症狀：** `cmd /c "run.bat"` 回傳 exit code 1，stdout/stderr 全空

**根本原因：** Kiro shell 工具在 Windows 環境對 `.bat` 執行有限制，帶引號路徑的指令也無法正常執行

**解法：** 把 `run.bat` 的功能改寫成 `run.py`，用 `subprocess` 依序執行各腳本，Kiro 可以直接跑 Python

**執行方式：**
```
python C:\openab\agent_skills\kiro\kiro7\goodinfo-trust\run.py
```

---

### 5. Agent Skills `name` 必須與目錄名稱一致

**症狀：** Skill 無法被正確識別或載入

**規範要求：** `SKILL.md` frontmatter 的 `name` 欄位必須與目錄名稱完全一致

**錯誤範例：** 目錄 `goodinfo-trust`，name 寫 `goodinfo-trust-win` ❌

**正確範例：** 目錄 `goodinfo-trust`，name 寫 `goodinfo-trust` ✅

---

### 6. SKILL.md 非標準 frontmatter 欄位

**症狀：** 在非 Kiro 環境下 Skill 行為異常

**說明：** `argument-hint`、`disable-model-invocation`、`allowed-tools` 是 Kiro 擴充欄位，不在 Agent Skills 開放標準內

**建議：** 若要跨工具相容，這些欄位移除或改寫進內文說明
