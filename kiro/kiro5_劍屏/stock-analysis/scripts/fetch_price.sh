#!/bin/bash
# fetch_price.sh - 抓取日K數據（支援上市 TWSE / 上櫃 OTC）
# 用法: ./fetch_price.sh {股票代號} {月數，預設3} {twse|otc，預設twse}
# 輸出: JSON 格式日K數據到 stdout

STOCK_CODE=$1
MONTHS=${2:-3}
MARKET=${3:-twse}

if [ -z "$STOCK_CODE" ]; then
  echo "ERROR: 請提供股票代號" >&2
  exit 1
fi

if [ "$MARKET" = "otc" ]; then
  # 上櫃股：使用 Yahoo Finance
  RANGE="3mo"
  case "$MONTHS" in
    1) RANGE="1mo" ;;
    2) RANGE="2mo" ;;
    6) RANGE="6mo" ;;
  esac
  curl -s "https://query2.finance.yahoo.com/v8/finance/chart/${STOCK_CODE}.TWO?interval=1d&range=${RANGE}"
else
  # 上市股：使用 TWSE
  START_MONTH=$(date -d "-${MONTHS} months" +%Y%m01 2>/dev/null || date -v-${MONTHS}m +%Y%m01)
  CURRENT_MONTH=$(date +%Y%m01)

  echo "["
  FIRST=1

  MONTH=$START_MONTH
  while [ "$MONTH" -le "$CURRENT_MONTH" ]; do
    RESP=$(curl -s "https://www.twse.com.tw/exchangeReport/STOCK_DAY?response=json&date=${MONTH}&stockNo=${STOCK_CODE}" 2>/dev/null)
    STAT=$(echo "$RESP" | grep -o '"stat":"[^"]*"' | cut -d'"' -f4)

    if [ "$STAT" = "OK" ]; then
      echo "$RESP" | grep -o '\["[^]]*"\]' | while IFS= read -r row; do
        DATE=$(echo "$row" | cut -d'"' -f2)
        VOL=$(echo "$row" | cut -d'"' -f4 | tr -d ',')
        OPEN=$(echo "$row" | cut -d'"' -f8)
        HIGH=$(echo "$row" | cut -d'"' -f10)
        LOW=$(echo "$row" | cut -d'"' -f12)
        CLOSE=$(echo "$row" | cut -d'"' -f14)
        CHANGE=$(echo "$row" | cut -d'"' -f16)

        if echo "$DATE" | grep -q "^[0-9]"; then
          if [ "$FIRST" = "0" ]; then echo ","; fi
          printf '{"date":"%s","open":%s,"high":%s,"low":%s,"close":%s,"volume":%s,"change":"%s"}' \
            "$DATE" "$OPEN" "$HIGH" "$LOW" "$CLOSE" "$VOL" "$CHANGE"
          FIRST=0
        fi
      done
    fi

    MONTH=$(date -d "${MONTH} +1 month" +%Y%m01 2>/dev/null || date -v+1m -j -f "%Y%m%d" "${MONTH}" +%Y%m01)
  done

  echo ""
  echo "]"
fi
