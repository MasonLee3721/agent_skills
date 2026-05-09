---
name: goodinfo-trust-win
description: >
  執行 Goodinfo 投信買超分析 pipeline（Windows 本地版）。
  當使用者說「跑投信」、「跑投本比」、「跑 Goodinfo」、「投信買超」時使用。
argument-hint: (無需參數)
disable-model-invocation: true
allowed-tools: Bash(cmd *)
---

# Skill: Goodinfo 投信買超分析（Windows 版）

## 觸發方式

使用者說以下任一關鍵字即觸發：
- 跑投信
- 跑投本比
- 跑 Goodinfo
- 投信買超
- 投信分析

## 前置條件

1. `C:\openab\goodinfo-scraper\` 已存在（公開 repo，可直接 clone）
2. 依賴已安裝（首次執行先跑 `setup.bat`）
3. `.env` 已設定 `DISCORD_BOT_TOKEN`（傳送 Discord 通知用）

若 goodinfo-scraper 不存在：
```cmd
"C:\Program Files\Git\cmd\git.exe" clone https://github.com/MasonLee3721/goodinfo-scraper.git C:\openab\goodinfo-scraper
```

## 執行方式

```cmd
cmd /c "C:\openab\agent_skills\kiro\kiro7\goodinfo-trust\run.bat" > C:\openab\goodinfo_run.log 2>&1
```

執行完畢後讀取 log：
```cmd
type C:\openab\goodinfo_run.log
```

## 執行流程

| 步驟 | 腳本 | 說明 |
|------|------|------|
| 1 | scrape_goodinfo.py | 爬投信買超排行，存 data/*.csv |
| 2 | scrape_foreign.py | 爬外資投信同買，存 data_foreign/*.csv |
| 3 | analyze.py | 分析連買天數與趨勢 |
| 4 | trust_trend.py | 篩選📈遞增+連買≥2天+買超≥0.2% |
| 5 | screen.py | 篩選買超≥0.68%且前30名 |
| 6 | recommend.py | 整合技術面，輸出推薦清單+K線圖 |

## 輸出

- 推薦清單：stdout（log 檔）
- K 線圖：`C:\openab\goodinfo-scraper\charts\{代號}.png`
- Discord 通知：傳送至設定的 channel（需 DISCORD_BOT_TOKEN）

## 首次安裝

```cmd
cmd /c "C:\openab\agent_skills\kiro\kiro7\goodinfo-trust\setup.bat"
```

## 注意事項

- 今日資料已存在時自動略過爬蟲（不重複抓）
- recommend.py 每支股票技術面分析需呼叫 TWSE/OTC API，約需 1~2 分鐘
- chart_draw 自動使用 Windows 版（微軟正黑體），執行完畢後自動還原原版
- 若 Goodinfo 被擋（回傳找不到資料表），等 5~10 分鐘後重試
