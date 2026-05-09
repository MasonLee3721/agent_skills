@echo off
setlocal

set PYTHON="C:\Program Files\Python314\python.exe"
set PYTHONPATH=C:\Users\swalz\AppData\Roaming\Python\Python314\site-packages;C:\Users\swalz\Python\Python314\site-packages
set SCRAPER=C:\openab\goodinfo-scraper
set SKILL_DIR=%~dp0
set SECRETS=%PYTHON% C:\openab\passkey\secrets_manager.py get

for /f "delims=" %%i in ('%SECRETS% DISCORD_BOT_TOKEN 2^>nul') do set DISCORD_BOT_TOKEN=%%i
for /f "delims=" %%i in ('%SECRETS% DISCORD_THREAD_ID 2^>nul') do set DISCORD_THREAD_ID=%%i
if not "%DISCORD_THREAD_ID%"=="" set DISCORD_CHANNEL_ID=%DISCORD_THREAD_ID%

echo [0/6] patch scripts for Windows...
%PYTHON% "%SKILL_DIR%patch_for_windows.py"

cd /d "%SCRAPER%"

echo [1/6] scrape_goodinfo...
%PYTHON% scrape_goodinfo.py
if errorlevel 1 goto error

echo [2/6] scrape_foreign...
%PYTHON% scrape_foreign.py
if errorlevel 1 goto error

echo [3/6] analyze...
%PYTHON% analyze.py
if errorlevel 1 goto error

echo [4/6] trust_trend...
%PYTHON% trust_trend.py
if errorlevel 1 goto error

echo [5/6] screen...
%PYTHON% screen.py
if errorlevel 1 goto error

echo [6/6] recommend + chart...
copy /y chart_draw.py chart_draw_bak.py >nul
copy /y "%SKILL_DIR%chart_draw_win.py" chart_draw.py >nul
%PYTHON% recommend.py > "%TEMP%\recommend_out.txt" 2>&1
type "%TEMP%\recommend_out.txt"
copy /y chart_draw_bak.py chart_draw.py >nul
del chart_draw_bak.py >nul

:: 傳推薦清單文字到 Discord thread
%PYTHON% -c "
import sys, os
sys.path.insert(0, r'C:\Users\swalz\AppData\Roaming\Python\Python314\site-packages')
sys.path.insert(0, r'C:\openab\goodinfo-scraper')
os.chdir(r'C:\openab\goodinfo-scraper')
from discord_send import send_text
txt = open(r'%TEMP%\recommend_out.txt', encoding='utf-8', errors='ignore').read()
# 只取推薦清單部分
start = txt.find('==')
msg = txt[start:].strip() if start >= 0 else txt.strip()
# Discord 訊息上限 2000 字
for i in range(0, len(msg), 1900):
    send_text(os.environ.get('DISCORD_CHANNEL_ID',''), msg[i:i+1900])
"

echo Done. Charts: %SCRAPER%\charts\
goto end

:error
echo FAILED.
exit /b 1

:end
endlocal
