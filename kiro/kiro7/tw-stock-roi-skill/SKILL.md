---
name: tw-stock-roi-skill
description: >
  直接對接台灣證券交易所 (TWSE) 與櫃買中心 (TPEx) 官方 REST/JSON API，
  即時抓取全市場上市與上櫃股票之三大法人與投信買賣超數據、實收資本額與發行張數，
  計算精確的投信買超投本比 TOP、投信賣超投本比 TOP 與上櫃買賣超清單，
  自動生成 HTML 視覺化暗黑風報表，並推送至 kiro-notes GitHub 儲存庫。
  當使用者提到「即時投信買賣超」、「跑新投本比」、「即時投本比」、「官方投本比」、
  「API投本比」、「TWSE投本比」、「全市場投本比」、「投賣比」、「投信結帳」時使用。
---

# Skill: 台灣股市官方 API 即時投本比計算與 HTML 發布

## 技能簡介
本技能直接對接證交所 (TWSE Open Data) 與櫃買中心 (TPEx API) 官方 JSON 數據，秒級精算全台股上市與上櫃股票之投信買賣超佔股本比例（投本比 %），自動生成具備暗黑風格、頁籤切換與搜尋篩選功能的 HTML 網頁報表，並自動發布至 `MasonLee3721/kiro-notes/kiro7_韋小寶/`。

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

## 輸出 URL 規範 (Required URLs on Completion)
每次執行本 Skill 完畢後，**必須在最終回覆中主動附上以下兩個 URL 連結**：
1. 🌐 **GitHub Pages 線上視覺化網頁 URL** (直接點擊看互動 UI 畫面):
   `https://masonlee3721.github.io/kiro-notes/kiro7_韋小寶/latest.html`
2. 📁 **GitHub 儲存庫原始檔 URL** (GitHub Repo Source File):
   `https://github.com/MasonLee3721/kiro-notes/blob/master/kiro7_韋小寶/latest.html`
