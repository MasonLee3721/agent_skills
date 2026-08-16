@echo off
setlocal
echo 啟動 Goodinfo 投信買超分析流程 (轉交由 run.py 跨平台執行)...
python "%~dp0run.py"
if errorlevel 1 (
    echo [ERROR] 執行失敗
    exit /b 1
)
endlocal
