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
%PYTHON% recommend.py
copy /y chart_draw_bak.py chart_draw.py >nul
del chart_draw_bak.py >nul

echo Done. Charts: %SCRAPER%\charts\
goto end

:error
echo FAILED.
exit /b 1

:end
endlocal
