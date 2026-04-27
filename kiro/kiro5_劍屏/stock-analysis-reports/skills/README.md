# 優分析小助理查詢 Skill

## 功能
登入 `pro.uanalyze.com.tw`，對指定股票查詢：
- **自動導航**（新手5步驟 / 進階6-10步 / 深度11-20步，raw text）
- **法人預估 EPS & 營收**（2022~2028 逐年表格）
- **小助理全19個主題**（近況發展、產業趨勢、產品線分析、長短期展望、供需分析、觀察重點、利多因素、利空因素、接單狀況、資本支出、新產品、時間表、相關公司、同業競爭、護城河分析、併購分析、重要數字、公司概覽、銷售地區）

結果存成 `公司名(股票代號)_查詢日期.md` 並 push 到 GitHub。

---

## 使用方式

### 1. 新 pod/session 啟動後，先執行環境設定（只需一次）
```bash
bash skills/setup_env.sh
```

### 2. 查詢股票
```bash
export PATH="/home/agent/.node/bin:$PATH"
export LD_LIBRARY_PATH="/tmp/libs/extracted/usr/lib/x86_64-linux-gnu:/tmp/libs/extracted/lib/x86_64-linux-gnu"
export FONTCONFIG_FILE="/tmp/fonts_conf/fonts.conf"

node skills/uanalyze_query.js 3533 嘉澤
node skills/uanalyze_query.js 2330 台積電
node skills/uanalyze_query.js NVDA NVIDIA
```

### 3. 結果
- 本地：`/tmp/stock-analysis-reports/公司名(代號)_日期.md`
- GitHub：`https://github.com/MasonLee3721/stock-analysis-reports`

---

## 環境變數
| 變數 | 說明 | 必填 |
|------|------|------|
| `UANALYZE_USERNAME` | 優分析帳號 email | ✅ |
| `UANALYZE_PASSWORD` | 優分析密碼 | ✅ |
| `REPORT_REPO` | GitHub repo（預設 `MasonLee3721/stock-analysis-reports`） | ❌ |

> gh CLI 需已登入（`gh auth status`）

---

## 技術架構

```
uanalyze_query.js
├── Playwright (headless Chrome)
│   ├── 登入 pro.uanalyze.com.tw
│   ├── 搜尋股票 → 觸發 /api/guides/{code}（自動導航）
│   ├── 點擊小助理 tab → 觸發 EPSRevenueConsensusEstimate
│   └── 逐一點擊19個主題按鈕 → 觸發 /completions?prompt={topic}
├── CDP (Chrome DevTools Protocol)
│   └── 攔截所有 twobitto / cronjob API 回應
└── 輸出 Markdown + push GitHub
```

### 關鍵 API
| API | 用途 |
|-----|------|
| `data.uanalyze.twobitto.com/api/guides/{code}` | 自動導航內容 |
| `cronjob.uanalyze.com.tw/data_fetch/api/EPSRevenueConsensusEstimate/{code}` | EPS & 營收預估 |
| `cronjob.uanalyze.com.tw/completions?prompt={topic}&stock={code}` | 小助理各主題 |

### Token 說明
`twobitto` 的 token 與主站相同（Bearer JWT），但**只能從瀏覽器內部發出才有效**（有 Origin 驗證），因此必須用 Playwright + CDP 攔截，不能直接 curl。

---

## 注意事項
- 每個主題等待 8 秒（API 回應時間），19 個主題約需 **2.5 分鐘**
- 若某主題無資料（如「併購分析」），會顯示「無相關資料」
- Token 有效期約 24 小時，每次執行都會重新登入取得新 token
