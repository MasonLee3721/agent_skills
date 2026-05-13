# goodinfo-joint：外資投信同買分析

## 篩選條件

| 條件 | 門檻 |
|------|------|
| 投信買超佔股本比（當日） | > 0.1% |
| 外資買超佔股本比（當日） | > 0.6% |
| 輸出筆數 | 前 10 檔（按外資%由高到低） |
| 附 K 線圖 | 前 5 檔 |

## 資料來源

- 投信：`C:\openab\goodinfo-scraper\data\YYYY-MM-DD.csv`（由 goodinfo-trust 爬取）
- 外資佔股本比：`C:\openab\goodinfo-scraper\data_foreign_pct\YYYY-MM-DD.csv`（本 skill 爬取）

## 執行方式

```
python C:\openab\agent_skills\kiro\kiro7\goodinfo-joint\run.py
```

## Pipeline

| 步驟 | 腳本 | 說明 |
|------|------|------|
| 1 | scrape_foreign_pct.py | 爬外資佔股本比排行 → data_foreign_pct/ |
| 2 | analyze_joint.py | JOIN 投信+外資，篩選，輸出報表，傳 Discord |

## 輸出格式

```
投外本比入榜（投信外資同買）
4966譜瑞-KY
投3.11、外3.44
...
```

## 觸發關鍵字

- 跑外資投信
- 跑聯合買超
- 跑外資投信同買
