#!/bin/bash
# setup_env.sh
# Playwright libs are pre-installed by the init container into /tmp/playwright-libs
# This script just installs Playwright Chromium if not present.

set -e

export PATH="/home/agent/.node/bin:$PATH"
export LD_LIBRARY_PATH="/tmp/playwright-libs"

if [ ! -f "/home/agent/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome" ]; then
  echo "📦 安裝 Playwright Chromium..."
  npx playwright install chromium 2>&1 | tail -3
fi

echo "✅ 環境設定完成！"
echo "測試 Chrome:"
/home/agent/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome --version 2>/dev/null || echo "⚠️  Chrome 測試失敗"
