---
name: active-etf-portfolio
description: >
  下載主動型 ETF（00981A，基金代碼 49YTW）每日持股 Excel，並與前日比對持股異動。
  當使用者提到「00981A」、「跑主動ETF」、「跑主動etf」、「主動ETF持股」、
  「下載主動ETF」、「ETF持股監測」、「ETF異動」、「Active ETF」時使用。
---

# Skill: 主動 ETF 持股下載與異動比對

## 執行方式

```cmd
python C:\openab\agent_skills\kiro\kiro7\active-etf-portfolio\active_etf_download.py 2>&1
```

## 功能說明

1. 用 Playwright（headless 模式）前往 ezmoney 網站下載 00981A（49YTW）持股 Excel
2. 儲存至 `data/active_etf_49YTW_YYYYMMDD.xlsx`（已存在則跳過下載）
3. 與前一份檔案比對，輸出持股異動

## 輸出格式

| 符號 | 意義 |
|------|------|
| `[+]` | 新買進 |
| `[^]` | 加碼 |
| `[v]` | 減碼 |
| `[-]` | 出清 |

每筆異動同時顯示**股票代號 + 股票名稱**，例如：
```
[+] 新買進：
   4958 臻鼎-KY  +1,428,000 股
[^] 加碼：
   2303 聯電  +5,700,000 股
[v] 減碼：
   2382 廣達  -5,440,000 股
[-] 出清：
   2404 漢唐  -1,200,000 股
```

股票名稱來源：Excel 中「股票名稱」欄（col B），ezmoney 下載的持股檔案原生提供，無需額外查詢。

## 資料目錄

```
C:\openab\agent_skills\kiro\kiro7\active-etf-portfolio\data\
```

檔名格式：`active_etf_49YTW_YYYYMMDD.xlsx`

## 前置條件

- Playwright 已安裝：`pip install playwright && playwright install chromium`
- openpyxl 已安裝：`pip install openpyxl`

## 注意事項

- 腳本使用 `headless=True`，可在無桌面環境（bot / CLI）正常執行
- openpyxl 讀取 ezmoney xlsx 會出現 "Workbook contains no default style" UserWarning，屬正常現象
- 比對需至少兩份歷史檔案；首次執行只會下載，不會輸出比對結果
- 資料來源：`https://www.ezmoney.com.tw/ETF/Fund/Info?fundCode=49YTW`
