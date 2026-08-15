---
name: tw-stock-roi-skill
description: >
  直接對接台灣證券交易所 (TWSE) 與櫃買中心 (TPEx) 官方 REST/JSON API，
  即時抓取全市場上市與上櫃股票之三大法人與投信買賣超數據、實收資本額與發行張數，
  計算精確的投信買超投本比 TOP、投信賣超投本比 TOP 與上櫃買賣超清單。
  當使用者提到「即時投信買賣超」、「跑新投本比」、「即時投本比」、「官方投本比」、
  「API投本比」、「TWSE投本比」、「全市場投本比」、「投賣比」、「投信結帳」時使用。
---

# Skill: 台灣股市官方 API 即時投本比計算 (TWSE / TPEx Direct API)

## 技能簡介
本技能不依賴第三方網頁爬蟲（無擋 IP、無 Captcha、無網頁結構異動風險），直接透過 HTTP 請求對接證交所 (TWSE Open Data) 與櫃買中心 (TPEx API) 的官方 JSON 數據，秒級精算全台股上市與上櫃股票之投信買賣超佔股本比例（投本比 %）。

## 觸發關鍵字 (Triggers)
- `即時投信買賣超` (主要觸發關鍵字)
- `跑新投本比`
- `即時投本比`
- `官方投本比`
- `API投本比`
- `TWSE投本比`
- `全市場投本比`
- `投賣比`
- `投信結帳`

## 運算公式
$$\text{投本比 (\%)} = \frac{\text{投信買賣超股數}}{\text{實收資本額} / 10} \times 100\% = \frac{\text{投信買賣超張數}}{\text{發行張數}} \times 100\%$$

## 執行方式

### 1. 執行單一命令產出即時報告
```bash
perl /home/agent/agent_skills/kiro/kiro7/tw-stock-roi-skill/scripts/calc_tw_stock_roi.pl
```

## 資料來源 (Data Sources)
1. **上市股票 (TWSE)**:
   - 股本與資本額：`https://openapi.twse.com.tw/v1/opendata/t187ap03_L`
   - 三大法人與投信買賣超日報：`https://www.twse.com.tw/rwd/zh/fund/T86?response=json&selectType=ALLBUT0999`
2. **上櫃股票 (TPEx)**:
   - 投信買超 TOP：`https://www.tpex.org.tw/www/zh-tw/insti/sitcStat?type=Daily&searchType=buy&response=json`
   - 投信賣超 TOP：`https://www.tpex.org.tw/www/zh-tw/insti/sitcStat?type=Daily&searchType=sell&response=json`

## 輸出範例內容
- 上市股票 投信買超投本比 TOP 20（股號、股票名稱、發行張數、買超張數、投本比%）
- 上市股票 投信賣超投本比 TOP 20（結帳警訊與拋售壓力）
- 上櫃股票 (TPEx) 投信買賣超焦點榜與重點個股分析
