# Troubleshooting

| 錯誤訊息 | 原因 | 解法 |
|----------|------|------|
| `UnicodeEncodeError: 'cp950'` | stdout 編碼問題 | 各腳本開頭已加 UTF-8 wrapper，run.bat 已加 `PYTHONIOENCODING=utf-8` |
| `技術面資料不足` | 新股歷史不足 65 天 | 正常現象，無需處理 |
| `Goodinfo 找不到資料表` | 被反爬蟲擋 | 等 5~10 分鐘後重試 |
| `DISCORD_BOT_TOKEN 未設定` | 直接跑 recommend.py 而非 run.bat | 改用 run.bat 執行完整流程 |
| `OTC API 回傳 HTML 404` | tpex.org.tw 舊 API 已失效 | 已改用 Yahoo Finance，此問題已修復 |
| `FAILED.` 在某步驟 | 該步驟腳本 exit code != 0 | 單獨跑該腳本看完整錯誤訊息 |
