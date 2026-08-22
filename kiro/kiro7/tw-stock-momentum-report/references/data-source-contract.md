# 官方資料介面契約

## 分層

將資料處理拆成三層，禁止抓取器直接產生 HTML：

1. `fetch`：取得原始回應，保存來源 URL、HTTP 狀態、取得時間與原始交易日。
2. `normalize`：轉成統一 record，不推估缺值、不做策略評分。
3. `analyze`：只接收正規化資料，呼叫 `momentum_core.py` 計算。

## 正規化鍵與單位

每筆法人資料至少包含：

```text
trade_date            YYYY-MM-DD
stock_code             字串
market                 TWSE 或 TPEx
foreign_net_shares     整數股或 null
sitc_net_shares        整數股或 null
source_name            字串
source_url             字串
fetched_at             含時區時間
```

唯一鍵為 `(trade_date, market, stock_code)`。所有法人原始量統一存「股」，僅在顯示層換算張。不能依 API 列號跨日期合併，必須依唯一鍵合併。

行情資料至少包含 `trade_date, stock_code, market, open, high, low, close, volume_shares`；公司資料至少包含 `stock_code, market, security_type, paid_in_capital_twd, issued_shares, par_value_twd, data_date`，並為估算欄位附 `is_estimated` 與公式。

## 失敗語意

- HTTP／JSON／schema 錯誤：該日期抓取失敗，不得寫成零買賣超。
- 休市：記錄為非交易日，不建立股票零值列。
- 個股欄位缺失：保留 null 及警告；初篩不得自動通過。
- 重跑同一唯一鍵：採可重入 upsert，但不得用較舊取得時間覆蓋較新資料。
- TWSE 與 TPEx 回傳日期不同：阻止合併成同日全市場排名。

## 腳本邊界

已建立 `scripts/fetch_official_data.py`，負責 TWSE T86 與 TPEx OpenAPI 的取得、schema 驗證、單位驗證、日期驗證及 normalized JSON 輸出。使用範例：

```text
python scripts/fetch_official_data.py --market all --date 2026-08-19 --output output/raw/institutional_20260819.json
```

只有兩市場回傳日期均等於指定日時，`--market all` 才能成功。TPEx OpenAPI 僅提供最新資料時，指定歷史日期會因日期不符而失敗，不得繞過。

已建立 `scripts/build_dataset.py`，依 `(market, stock_code)` 合併法人、行情及公司資料，排除非普通股，阻止法人／行情跨日，並輸出逐檔排除原因及激進／穩健初篩結果。若法人輸入沒有截至指定日的 `sitc_history`，連買日數必須為 null，兩種模式不得通過連買條件。相關腳本須支援 `--date YYYY-MM-DD`、明確逾時、有限重試、非零失敗碼及離線 fixture 測試。先用 fixture 測試 parser，再以單一已完成交易日做小規模官方 API 驗證；未驗證 schema 前不得進行全期間回補。

## 分階段抓取限制

`build_dataset.py` 的 `preselection` 只使用全市場單日資料，不得把尚未取得的連買或技術條件當成預選失敗。執行 `select_history_targets.py` 後，歷史法人與 OHLCV 抓取器只能接受其 `targets`；禁止直接以全市場公司清單抓歷史資料。預設每個預選股抓 10 個交易日法人與 120 個交易日行情，最低分別為 3 日與 60 日。

## 公司母體來源

`scripts/fetch_company_universe.py` 使用 TWSE `t187ap03_L` 與 TPEx `mopsfin_t187ap03_O` 公司基本資料，直接保存官方已發行普通股數、實收資本額及面額。不得以實收資本額除以 10 覆蓋官方股數。無面額或非 10 元面額仍可使用官方發行股數計算投本比；面額欄保持 null 或實際值。公司資料日期按市場及逐筆保存，允許與法人交易日不同，但報告必須揭露。

## 單日行情來源

`scripts/fetch_daily_quotes.py` 使用 TWSE `STOCK_DAY_ALL` 與 TPEx `tpex_mainboard_daily_close_quotes`，保存 OHLC、漲跌及成交股數。兩市場官方 OpenAPI 必須回傳相同指定日期，`--market all` 才可成功。缺少完整 OHLC 者 `trading_status_ok=false`；成交量缺失或為零者 `liquidity_status_ok=false`。全市場行情只用於低成本預選，歷史行情仍只抓 `select_history_targets.py` 輸出的目標。

## 候選股歷史資料

`scripts/fetch_institutional_history.py` 逐交易日取得 TWSE T86 或 TPEx `insti/dailyTrade` 全表，但只保存目標清單中的股票；缺少個股列時保存 null 與警告，不可填 0。`scripts/fetch_price_history.py` 逐月取得 TWSE `STOCK_DAY` 或 TPEx `afterTrading/tradingStock`；TWSE 成交量為股，TPEx 成交量為張，正規化時乘 1,000。官方除權息漲跌值可能帶 `X` 註記，須剝離註記但保留數值。行情請求必須節流；大量目標應使用斷點快取，遇 307／限流不得產出半套報告。

## 官方行情備援與降級規則（Schema 2.0）

TWSE `STOCK_DAY_ALL` 日期落後時，只能以目標日期查詢官方 `MI_INDEX`；回傳 `stat=OK`、日期完全相符且存在完整收盤行情表才可採用。正規化記錄標示 `source_name=TWSE MI_INDEX`。TPEx 不得使用 MI_INDEX，仍使用櫃買官方行情。

個股歷史行情只缺最後一個營業日時，可由已驗證的同日全市場 OHLCV 補齊，並標示 `daily_fallback_applied=true`、`data_status=actual_fallback`。缺兩個以上平日不得補造。

候選技術資料失敗不得中止全體：保留候選、兩個技術分項均為 0、`technical_status=missing`、可信度低、`trading_plan=null`，並保存結構化失敗原因。
