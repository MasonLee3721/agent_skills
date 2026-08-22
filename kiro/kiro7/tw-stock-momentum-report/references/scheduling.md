# 每日排程

正式排程部署在 `MasonLee3721/kiro-notes` 的 `.github/workflows/daily-tw-stock-momentum-report.yml`。

- 每天台灣時間 17:30 執行；GitHub Actions cron 為 `30 9 * * *`（UTC）。
- 支援 `workflow_dispatch` 手動測試。
- 從 `MasonLee3721/agent_skills@main` 取得本 Skill。
- 執行 `scripts/run_scheduled_daily.py`，每 15 分鐘重試一次，最多 16 次。
- 驗證成功後只更新 `kiro-notes/master` 內最新版 HTML、日期版 HTML、報告 JSON 與執行狀態。
- 週末或國定假日仍會執行；若交易日及報告內容未變，不建立新 Commit。
- 失敗時保留上一份 `latest.html`，不得發布半套報告。

本機 cron 不作為正式排程，避免臨時容器重啟後排程消失。
