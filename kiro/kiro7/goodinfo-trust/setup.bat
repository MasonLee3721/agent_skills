@echo off
echo 安裝 goodinfo-trust 所需套件...
"C:\Program Files\Python314\python.exe" -m pip install beautifulsoup4==4.13.4 lxml==5.3.2 pandas mplfinance matplotlib yfinance python-dotenv
echo.
echo 安裝完成
pause
