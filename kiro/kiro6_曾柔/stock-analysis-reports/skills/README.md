# 曾柔的優分析 Skills

從劍屏那邊複製過來的，兩個腳本功能如下：

## 腳本說明

### uanalyze_basic.js（自動導航）
- 功能：優分析「自動導航」，抓 20 個 STEP 的圖表數字（月營收、EPS、季預估、資本支出、存貨等）
- 執行：`node uanalyze_basic.js <股票代號> <股票名稱>`
- 例：`node uanalyze_basic.js 3624 光頡`

### uanalyze_advance.js（小助理）
- 功能：優分析「小助理」17 個主題（近況發展、產業趨勢、利多利空、護城河...等）
- 執行：`node uanalyze_advance.js <股票代號> <股票名稱>`
- 例：`node uanalyze_advance.js 3624 光頡`

## 執行前設定

```bash
export PATH="/home/agent/.node/bin:$PATH"
export LD_LIBRARY_PATH="/tmp/playwright-libs"
export $(cat /proc/1/environ | tr '\0' '\n' | grep UANALYZE)
```

## 報告輸出
- 自動存到 `reports/` 目錄
- 自動 push 到 GitHub

## 參考劍屏的報告
- 劍屏的報告在：`kiro/kiro5_劍屏/stock-analysis-reports/reports/`
