---
name: goodinfo-trust
description: >
  執行台股投信買超分析 pipeline，整合技術面篩選後輸出推薦清單並傳送 Discord 通知。
  當使用者提到「投信買超」、「投本比分析」、「跑 Goodinfo」、「今日推薦股」、
  「跑投信」、「投信分析」、「跑投本比」時使用。
---

# Skill: 台股投信買超分析

## 執行方式

跨平台（Windows / Linux）推薦統一使用 Python 執行：

```bash
python kiro/kiro7/goodinfo-trust/run.py
```

Windows 批次檔執行方式：

```cmd
cmd /c "%CD%\kiro\kiro7\goodinfo-trust\run.bat"
```

## 前置條件

1. `goodinfo-scraper` 儲存庫已下載（同級目錄或指定 `SCRAPER_DIR`）
   - 最低相容 Commit：`goodinfo-scraper` Commit `@9a6ffb9` 或更新版本（支援 `CHART_SCRIPT` 原生載入）
   - 若不存在：`git clone https://github.com/MasonLee3721/goodinfo-scraper.git`
2. `DISCORD_BOT_TOKEN` 已設定於系統環境變數或 `passkey/secrets_manager.py`
3. 首次執行先執行套件安裝（`pip install -r requirements.txt` 或 `setup.bat`）

## Pipeline 步驟

| 步驟 | 腳本 | 說明 |
|------|------|------|
| 1 | scrape_goodinfo.py | 爬投信買超排行 → data/*.csv |
| 2 | scrape_foreign.py | 爬外資投信同買 → data_foreign/*.csv |
| 3 | analyze.py | 分析連買天數與趨勢 |
| 4 | trust_trend.py | 篩選 📈遞增 + 連買≥2天 + 買超≥0.2% |
| 5 | screen.py | 篩選買超≥0.68% 且前30名 |
| 6 | recommend.py | 技術面分析 + K線圖 + Discord 傳送 |

## 技術面分析說明

`recommend.py` 對每支候選股呼叫 Yahoo Finance API（`.TW` / `.TWO` 自動判斷），
計算以下 6 項條件：

1. 均線多頭排列：5MA > 20MA > 60MA
2. 20MA 向上斜（今日 > 5日前）
3. RSI(14) 介於 50~80
4. 近 5 日漲幅 > 0
5. 今日量 > 5日均量 × 1.5（放量）
6. 創 20 日新高

技術分 ≥ 4/6 才列入推薦。

## 腳本說明

- `run.py`：主流程，自動探測路徑、注入環境變數、動態載入 `CHART_SCRIPT`
- `send_recommend.py`：讀取 recommend 輸出 log，分段傳送至 Discord（每段 1900 字）
- `chart_draw_win.py`：K 線圖繪製腳本，具備中文字型降級與跨平台相容性

## 注意事項

- 今日資料已存在時自動略過爬蟲（不重複抓）
- 技術面分析每支約 1~2 秒（Yahoo Finance API）
- 詳細流程說明：`references/pipeline.md`
- 常見錯誤排查：`references/troubleshooting.md`

## 金融數據治理與資料誠信原則 (MasonLee 大老闆核心指令)

1. **Raw Data ≠ Derived Data ≠ Estimated Data**：三者必須完全分離。絕不捏造、模擬或拿價格估算任何真實財務與籌碼指標 (如法人買賣超、營收、成交量、價格)。
2. **零偽造籌碼法則 (Zero Synthetic Data Rule)**：嚴禁使用 Trend Curve Fitting 擬真演算法、隨機生成器或推測邏輯冒充官方真實法人買賣超。
3. **官方數據庫與增量更新架構 (Incremental Sync Engine)**：
   - 採用「TWSE / TPEx 官方歷史資料回補 + 本地 JSON/SQLite 資料庫 (`t86_real_database.json`) + 每日增量更新 (`institutional_data_engine.pl`)」架構。
   - 繪圖與指標計算 100% 只從本地官方真實資料庫調用外資與投信原始張數。
   - 若歷史資料尚未回補完成，明確標示 `[目前歷史資料尚未回補完成]` 或 `N/A`，絕不偽造數據冒充官方實際值。
