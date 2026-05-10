# Pipeline 詳細說明

## 資料流

```
Goodinfo 網站
    └─ scrape_goodinfo.py → data/YYYY-MM-DD.csv
                              欄位：代號, 名稱, 排名, 當日買賣超佔發行張數, 成交

Goodinfo 網站
    └─ scrape_foreign.py → data_foreign/YYYY-MM-DD.csv
                              欄位：代號, 名稱, 成交, 漲跌價, 漲跌幅, 成交張數

data/*.csv
    └─ analyze.py → stdout（連買天數、趨勢分析，389+ 支）

data/*.csv + data_foreign/*.csv
    └─ trust_trend.py → stdout（📈遞增 + 連買≥2天 + 買超≥0.2%）
                      → charts/*.png（前5支 K 線圖）

data/*.csv
    └─ screen.py → stdout（買超≥0.68% 且前30名，含外資同買標記）

data/*.csv + data_foreign/*.csv + Yahoo Finance API
    └─ recommend.py → stdout（推薦清單 + 技術明細）
                    → charts/*.png（推薦股 K 線圖）
                    → Discord（透過 send_recommend.py）
```

## 篩選條件

### trust_trend.py
- 買超佔股本比 ≥ 0.2%
- 連買 ≥ 2 天
- 趨勢：📈 遞增（最近幾天買超幅度持續增加）

### screen.py（投信認養名單）
- 買超佔股本比 ≥ 0.68%
- 排名前 30

### recommend.py（最終推薦）
- 符合 screen.py 條件
- 技術面 ≥ 4/6 條件通過

## K 線圖

- 來源：yfinance（Yahoo Finance）
- 格式：mplfinance candlestick
- 字型：Windows 版使用微軟正黑體（chart_draw_win.py）
- 輸出：`C:\openab\goodinfo-scraper\charts\{代號}.png`
- run.bat 執行時自動替換 chart_draw.py → chart_draw_win.py，結束後還原
