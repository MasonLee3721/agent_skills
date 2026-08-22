# 每日排程建議

建議於台灣時間 18:30 啟動，避免交易所盤後資料尚未同步。包裝器預設每 15 分鐘重試一次，共 16 次，最多涵蓋 4 小時。

```cron
CRON_TZ=Asia/Taipei
30 18 * * 1-5 cd /home/node/agent_skills_review/kiro/kiro7/tw-stock-momentum-report && /home/node/.local/bin/uv run --python 3.12 scripts/run_scheduled_daily.py --output-dir output --attempts 16 --interval-seconds 900
```

排程只應在確認實際部署路徑與執行帳號後安裝。國定假日會由四來源交易日一致性檢查處理；若沒有新資料，保留上一份 latest.html 並寫入失敗狀態與日誌。
