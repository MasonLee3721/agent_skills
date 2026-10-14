---
name: active-etf-portfolio
description: >
  下載主動型 ETF（00981A，基金代碼 49YTW）每日持股 Excel，並與前一份比對持股異動。
  當使用者提到「00981A」、「跑主動ETF」、「跑主動etf」、「主動ETF持股」、
  「下載主動ETF」、「ETF持股監測」、「ETF異動」、「Active ETF」時使用。
---

# Skill: 主動 ETF 持股下載與異動比對

## 執行方式（Linux / K8s pod）

```bash
cd /home/agent/agent_skills/kiro/kiro7/active-etf-portfolio
/home/agent/.local/bin/uv run --with requests --with openpyxl python active_etf_download.py
```

> 系統 Python 由 uv 管理（PEP 668 externally-managed），不可 `pip install`；
> 依賴一律用 `uv run --with` 臨時注入。

## 功能說明

1. **主要路徑：HTTP 直接下載**（不需瀏覽器）
   - 先 GET `https://www.ezmoney.com.tw/ETF/Fund/Info?fundCode=49YTW` 取得 Session cookie
   - 再下載 `https://www.ezmoney.com.tw/ETF/Fund/AssetExcelNPOI?fundCode=49YTW`
2. **降級路徑：Playwright**（僅在 HTTP 失敗時嘗試；容器內預設未安裝，失敗即報錯）
3. 儲存至 `data/active_etf_49YTW_YYYYMMDD.xlsx`（當日檔已存在則跳過下載）
4. 與 `data/` 內前一份檔案比對，輸出持股異動

## 輸出格式

| 符號 | 意義 |
|------|------|
| `[+]` | 新買進 |
| `[^]` | 加碼 |
| `[v]` | 減碼 |
| `[-]` | 出清 |

每筆異動顯示**股票代號 + 股票名稱 + 股數變化**，例如：
```
[^] 加碼：
   2330 台積電  +364,000 股
[v] 減碼：
   2383 台光電  -322,000 股
```

股票名稱來源：Excel「股票名稱」欄（col B），ezmoney 原生提供。

## 資料目錄

```
/home/agent/agent_skills/kiro/kiro7/active-etf-portfolio/data/
```

檔名格式：`active_etf_49YTW_YYYYMMDD.xlsx`（日期為下載當天，非持股基準日）

## 注意事項

- openpyxl 會出現 `Workbook contains no default style` UserWarning，屬正常現象
- 比對需至少兩份歷史檔案；首次執行只下載、不比對
- **比對對象是「上一份檔案」而非「上一個交易日」**：若中間有幾天沒跑，異動會是多日累積
- 執行的是**本機版本**，不會自動 `git pull`；GitHub 上的更新需手動同步
- 資料來源：`https://www.ezmoney.com.tw/ETF/Fund/Info?fundCode=49YTW`
