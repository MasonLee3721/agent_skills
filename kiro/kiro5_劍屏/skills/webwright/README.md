# Webwright Skill

來源：https://github.com/microsoft/Webwright

## 是什麼

用 Playwright Firefox 瀏覽器自動完成網頁任務的 skill。
每個任務會產生可重跑的 Python 腳本 + 截圖 + 執行紀錄。

## 使用方式

### 一次性任務
```
/webwright:run 在 Google Flights 搜尋 2026-08-15 台北飛東京的最便宜機票
```

### 產生可重用 CLI 工具
```
/webwright:craft 在 Google Flights 搜尋 2026-08-15 台北飛東京的最便宜機票
```
產出的 `final_script.py` 可以之後用不同參數重跑：
```bash
python final_script.py --origin TPE --dest TYO --date 2026-09-01
```

## 產出結構

```
outputs/<task_id>/
├── plan.md                          ← 任務拆解成 Critical Points
└── final_runs/run_1/
    ├── final_script.py              ← 可重跑的腳本
    ├── final_script_log.txt         ← 執行紀錄 + 最終結果
    └── screenshots/
        └── final_execution_1_*.png  ← 每個關鍵步驟截圖
```

## 環境需求

- Firefox playwright 已安裝：`/home/agent/.cache/ms-playwright/firefox-1522/`
- Python playwright：`uv run --with playwright`
- 不需要任何 API key

## 檔案說明

| 檔案 | 說明 |
|------|------|
| `SKILL.md` | 完整 skill 規格（agent 讀這個） |
| `commands/run.md` | `/webwright:run` 指令定義 |
| `commands/craft.md` | `/webwright:craft` 指令定義 |
| `reference/workflow.md` | 6步驟工作流程詳細說明 |
| `reference/playwright_patterns.md` | Playwright 程式碼範本 |
| `reference/cli_tool_mode.md` | CLI 工具模式規格 |

## 安裝日期
2026-05-28
