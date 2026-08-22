---
name: tw-stock-momentum-report
description: 使用最新已完成交易日的可驗證資料，篩選台灣上市與上櫃普通股的投信投本比、連買、外資同步與技術動能，產生互動式 HTML、機器可讀 JSON、候選排名及條件式風險規劃。使用者要求台股投本比短線波段篩選、投信籌碼動能排名、激進／穩健候選、法人與 K 線整合分析或發布每日動能報告時使用。
---

# 台股投本比動能報告

## 核心原則

以資料正確性優先於完成率。只使用最新已完成交易日；不得將盤中值稱為收盤值，不得補造缺值，不得把估算值寫成實際值，也不得保證獲利。

執行前完整讀取：

- [資料、篩選與評分規格](references/data-and-scoring.md)：取得資料、計算、篩選或評分前讀取。
- [報告與交付契約](references/report-contract.md)：產生 HTML、JSON 或最終摘要前讀取。
- [官方資料介面契約](references/data-source-contract.md)：實作或修改 TWSE／TPEx 抓取、歷史回補與資料合併時讀取。

可重用純計算核心位於 `scripts/momentum_core.py`；官方法人抓取器位於 `scripts/fetch_official_data.py`；官方公司／實際發行股數抓取器位於 `scripts/fetch_company_universe.py`；官方單日行情抓取器位於 `scripts/fetch_daily_quotes.py`；正規化資料合併器位於 `scripts/build_dataset.py`；歷史抓取目標產生器位於 `scripts/select_history_targets.py`；候選股法人與行情回補器位於 `scripts/fetch_institutional_history.py`、`scripts/fetch_price_history.py`；每日模式分類、評分與報告腳本位於 `scripts/finalize_daily_candidates.py`、`scripts/build_daily_scores.py`、`scripts/render_daily_report.py`。每日單一入口為 `scripts/run_daily_screen.py`，排程重試入口為 `scripts/run_scheduled_daily.py`。修改後執行 `uv run --python 3.12 python -m unittest discover -s tests -v`。抓取器不得直接重寫核心公式。

## 執行流程

### 每日單一命令

一般手動執行時省略日期，由四個官方來源交叉確認最新已完成交易日：

```bash
uv run --python 3.12 scripts/run_daily_screen.py --output-dir output
```

排程使用重試包裝器；預設每 15 分鐘重試、最多 16 次。安裝 cron 前先閱讀 [每日排程建議](references/scheduling.md)：

```bash
uv run --python 3.12 scripts/run_scheduled_daily.py --output-dir output --attempts 16 --interval-seconds 900 --publish
```

加上 `--publish` 時，僅在報告成功且 HTML／JSON 交易日期一致後，將 `latest.html`、日期版 HTML、報告 JSON 與執行狀態複製到 `MasonLee3721/kiro-notes` 的 `master` 分支。Skill 原始碼留在 `agent_skills`；發布器使用全新淺層 clone，不得提交快取、中間資料或其他檔案。檢查 `output/data/daily_run_status.json`、`output/logs/` 以及命令回傳碼。暫時錯誤不得覆蓋上一份 `latest.html`；非暫時錯誤不得無限重試。

### 1. 稽核能力與輸入

確認可取得 TWSE／TPEx 法人資料、普通股清單與交易狀態、資本與發行股數、至少 60 日 OHLCV、至少近 3 日外資與投信資料，以及可寫入的輸出目錄。

缺少能力時先列出缺口；仍執行可驗證部分，但不得用替代假資料湊齊結果。若使用者只要求規劃或檢查，不要抓資料、寫報告或發布。

### 2. 鎖定日期

找出最新已完成交易日，分別記錄行情、法人、公司資料日期及取得時間／時區。價格、成交量與法人日期不一致時，在報告頂部警告並降低可信度；禁止靜默混用。

### 3. 建立股票母體

合併上市與上櫃普通股，排除 ETF、ETN、權證、特別股、存託憑證、債券及其他非普通股。無法確認商品類型、停止交易、處置狀態或流動性異常者原則上排除；保留時明示風險。

以股票代號、交易日及市場作鍵合併，禁止依回傳列序硬接。保留原始單位，衍生欄位另算並標示來源。

### 4. 計算、初篩與分類

先用全市場單日資料執行預選：投本比／前30名、當日投信淨買超、成交量、資本額、普通股及交易狀態。僅將 `preselection.passed=true` 的股票交給 `scripts/select_history_targets.py`，再抓近 3～10 日法人與 60～120 日行情。取得歷史後才判斷連買與技術面；激進模式連買至少 1 日，穩健模式至少 3 日。資料不足判為未知，不得自動通過。

### 5. 評分與可信度

只為通過初篩者計算 0～100 分，保存每項輸入、得分與理由。可信度分高／中／低：核心資料同日且無估算為高；明示估算或次要缺失但核心可驗證為中；日期錯位、來源受限或關鍵缺失為低。總分不得掩蓋可信度。

### 6. 產生報告

依報告契約產生：

```text
output/latest.html
output/tw_stock_momentum_report_YYYYMMDD.html
output/data/report_YYYYMMDD.json
```

HTML 主要內容須可在無後端環境查看，並 escape 外部文字。JSON 保留原始精度與資料血緣；HTML 僅格式化顯示。互動圖表使用 ECharts 或 TradingView Lightweight Charts；歷史不足顯示實際筆數，不得補造。

### 7. 驗證後交付

驗證日期、股／張換算、投本比分母、商品排除、排名與評級邊界、HTML escaping、手機版、tooltip 及 HTML／JSON 一致性。隨機抽查至少 5 筆法人原始值；樣本不足時全查。

關鍵驗證失敗時不得宣稱完成或發布。除非使用者明確授權，不要 commit、push、傳送 Discord、登入外部服務或執行交易。

## 禁止事項

- 不得捏造行情、成交量、法人籌碼、持股比例、技術指標或績效。
- 不得將期間累計買超比例稱為實際持股比例。
- 不得將實收資本額與市值混用。
- 不得假設所有股票面額均為新台幣 10 元。
- 不得用盤中跌破描述收盤退出訊號。
- 不得自動下單、登入券商或送出委託。
