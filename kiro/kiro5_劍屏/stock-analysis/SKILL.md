---
name: stock-analysis
description: 對台股進行完整的基本面 + 技術面分析，輸出標準化投資建議報告。當使用者說「分析 [股票代號] [公司名稱]」或「幫我看 [公司名稱]」時使用。
argument-hint: [股票代號] [公司名稱]
arguments: stock_code company_name
disable-model-invocation: true
allowed-tools: Bash(curl *) Bash(awk *) Bash(cat *) Bash(bash *) Bash(mkdir *) Bash(date *) Write
---

# Skill: 台股分析報告

## 觸發方式
```
/stock-analysis {股票代號} {公司名稱}
例：/stock-analysis 3048 益登
```

## 前置條件
**本 skill 不查詢優分析，需先由使用者執行 uanalyze-query skill 完成查詢。**
優分析報告路徑：`/home/agent/notes/uanalyze/{公司名稱}({股票代號})_YYYYMMDD.md`

---

## 執行步驟

### Step 1：讀取優分析報告

```bash
ls /home/agent/notes/uanalyze/ | grep "$stock_code" | sort | tail -1
```

找到最新的當日報告後讀取全文。若找不到，告知使用者先執行 uanalyze-query。

### Step 2：抓取日K數據

**先判斷上市/上櫃：**
- 上市（TWSE）：代號開頭通常為 1xxx~3xxx（部分例外）
- 上櫃（OTC）：代號開頭通常為 4xxx~9xxx（部分例外）
- 不確定時，先試 TWSE，若回傳資料為空再改 OTC

**上市股（TWSE）：**
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/fetch_price.sh $stock_code 3 twse
```
若腳本異常，直接 curl：
```bash
curl -s "https://www.twse.com.tw/exchangeReport/STOCK_DAY?response=json&date=$(date +%Y%m01)&stockNo=$stock_code"
```
即時報價：
```bash
curl -s "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=tse_${stock_code}.tw&json=1&delay=0"
```

**上櫃股（OTC）：改用 Yahoo Finance**
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/fetch_price.sh $stock_code 3 otc
```
若腳本異常，直接 curl：
```bash
curl -s "https://query2.finance.yahoo.com/v8/finance/chart/${stock_code}.TWO?interval=1d&range=3mo"
```
即時報價：
```bash
curl -s "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=otc_${stock_code}.tw&json=1&delay=0"
```

### Step 3：計算技術指標

依照 `references/ta-guide.md` 的規則，用 awk 計算以下指標。
**所有數值必須實際計算，不得估算或捏造。**

**計算順序：**
1. 整理收盤價序列（時間正序，取最近 60 筆）
2. MA5、MA20、MA60
3. 布林通道（基於 MA20）
4. RSI(14)（Wilder 平滑法）
5. EMA12、EMA26 → MACD(DIF/DEA/Histogram)
6. KD(9,3,3)（初始值 K=D=50）
7. MAV5、MAV20、MAV60（成交量，單位：張）
8. 均線型態判斷（排列 + 糾結 + 方向）
9. 關鍵價位識別（近20日高低點）

**均線型態判斷邏輯（必須輸出）：**
- 排列狀況：MA5 vs MA20 vs MA60 的大小關係
- 各線方向：與 5 日前比較（向上/向下/走平，差距 < 0.5% 為走平）
- 糾結判斷：abs(MA5-MA20)/MA20 < 2% 且 abs(MA20-MA60)/MA60 < 2%
- 交叉訊號：檢查最近 5 日是否有 MA5 穿越 MA20

### Step 4：基本面分析

從優分析報告中提煉：
1. **只保留有數字支撐的事實**，剔除純題材敘事
2. **區分本業 EPS 與合併 EPS**，一次性事件不計入估值
3. 找出核心成長動能（最多 3 條）
4. 找出主要風險（最多 3 條）
5. 計算合理估值區間：本業 EPS × 合理本益比（參考產業中位數）

### Step 5：產出報告

依照 `references/output-format.md` 的模板格式輸出完整報告。

**必須包含：**
- 結論先行（一句話）
- 基本面摘要（含財務快照 + 估值區間）
- 技術指標（均線 + 均線型態 + 布林 + 動能指標 + 成交量均線）
- 關鍵價位（至少 2 壓力 + 2 支撐）
- 未來路徑評估（三情境，機率加總 = 100%）
- 操作建議（明確 Do / Don't）
- 綜合評分

### Step 6：存檔

```bash
mkdir -p /home/agent/notes/stock-analysis
# 存檔路徑：/home/agent/notes/stock-analysis/{公司名稱}({股票代號})_analysis_{YYYYMMDD}.md
```

### Step 7：Push GitHub

```bash
cd /home/agent/notes
git add stock-analysis/
git commit -m "add: {公司}({代號}) 股票分析報告 $(date +%Y%m%d)"
git push
```

### Step 8：回報

完成後 mention <@1331833906751869030> 並附上報告摘要（結論 + 操作建議）。

---

## 參考文件

- 技術指標計算規則：[references/ta-guide.md](references/ta-guide.md)
- 報告輸出格式：[references/output-format.md](references/output-format.md)
- 日K數據腳本：[scripts/fetch_price.sh](scripts/fetch_price.sh)

---

## 注意事項

- 若優分析報告不存在，停止執行並提示使用者先跑 uanalyze-query
- 若 TWSE 數據不足 20 筆，布林通道無法計算，需說明
- 若 TWSE 數據不足 60 筆，跳過 MA60 相關計算，在報告中標注「資料不足」
- 技術指標數值必須實際計算，不得憑印象填寫
