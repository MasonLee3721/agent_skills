---
name: goodinfo-trust
description: >
  執行台股投信買超分析 pipeline，整合技術面篩選後輸出推薦清單並傳送 Discord 通知。
  當使用者提到「投信買超」、「投本比分析」、「跑 Goodinfo」、「今日推薦股」、
  「跑投信」、「投信分析」、「跑投本比」時使用。
---

# Skill: 台股投信買超分析

## 執行方式

```cmd
cmd /c "C:\openab\agent_skills\kiro\kiro7\goodinfo-trust\run.bat" > C:\openab\goodinfo_run.log 2>&1
type C:\openab\goodinfo_run.log
```

## 前置條件

1. `C:\openab\goodinfo-scraper\` 已存在
   - 若不存在：`git clone https://github.com/MasonLee3721/goodinfo-scraper.git C:\openab\goodinfo-scraper`
2. `DISCORD_BOT_TOKEN` 已設定於 `C:\openab\passkey\secrets_manager.py`
3. 首次執行先跑 `setup.bat`

## Pipeline 步驟

| 步驟 | 腳本 | 說明 |
|------|------|------|
| 0 | patch_for_windows.py | Windows 相容性修正（一次性） |
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

- `run.bat`：主流程，自動注入 DISCORD_BOT_TOKEN，設定 PYTHONIOENCODING=utf-8
- `patch_for_windows.py`：修正 trust_trend.py 的 Linux uv 指令為 sys.executable
- `send_recommend.py`：讀取 recommend 輸出 log，分段傳送至 Discord（每段 1900 字）
- `chart_draw_win.py`：Windows 版 K 線圖，使用微軟正黑體，執行後自動還原原版

## 注意事項

- 今日資料已存在時自動略過爬蟲（不重複抓）
- 技術面分析每支約 1~2 秒（Yahoo Finance API）
- 詳細流程說明：`references/pipeline.md`
- 常見錯誤排查：`references/troubleshooting.md`
