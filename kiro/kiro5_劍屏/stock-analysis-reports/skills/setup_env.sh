#!/bin/bash
# setup_env.sh
# 在新的 pod/session 啟動後執行此腳本，安裝 Playwright 所需的系統 libs
# 使用方式: bash setup_env.sh

set -e
echo "🔧 安裝 Playwright 系統依賴..."

mkdir -p /tmp/libs/extracted /tmp/fonts_conf /tmp/fonts_cache
BASE="http://ftp.us.debian.org/debian/pool/main"

download_and_extract() {
  local dir=$1 pkg=$2
  local VER=$(curl -s "$BASE/$dir/" | grep -oP "${pkg}_[^\"]+amd64\.deb" | grep -v "dev\|doc\|dbg" | tail -1)
  [ -z "$VER" ] && echo "  ⚠️  $pkg not found" && return
  curl -sL "$BASE/$dir/$VER" -o "/tmp/libs/${pkg}.deb" 2>/dev/null
  local SIZE=$(wc -c < "/tmp/libs/${pkg}.deb")
  [ "$SIZE" -gt 1000 ] && dpkg-deb -x "/tmp/libs/${pkg}.deb" /tmp/libs/extracted/ 2>/dev/null && echo "  ✓ $pkg" || echo "  ✗ $pkg (${SIZE}b)"
}

# Core libs
download_and_extract "g/glib2.0" "libglib2.0-0"
download_and_extract "n/nss" "libnss3"
download_and_extract "n/nspr" "libnspr4"
download_and_extract "a/at-spi2-core" "libatk1.0-0"
download_and_extract "a/at-spi2-core" "libatspi2.0-0"
download_and_extract "a/at-spi2-core" "libatk-bridge2.0-0"
download_and_extract "d/dbus" "libdbus-1-3"
download_and_extract "libx/libdrm" "libdrm2"
download_and_extract "libx/libxkbcommon" "libxkbcommon0"
download_and_extract "libx/libxcomposite" "libxcomposite1"
download_and_extract "libx/libxdamage" "libxdamage1"
download_and_extract "libx/libxfixes" "libxfixes3"
download_and_extract "libx/libxrandr" "libxrandr2"
download_and_extract "m/mesa" "libgbm1"
download_and_extract "a/alsa-lib" "libasound2"
download_and_extract "s/sqlite3" "libsqlite3-0"
download_and_extract "c/cups" "libcups2"
download_and_extract "w/wayland" "libwayland-server0"
download_and_extract "w/wayland" "libwayland-client0"
download_and_extract "libx/libx11" "libx11-6"
download_and_extract "libx/libxcb" "libxcb1"
download_and_extract "libx/libxext" "libxext6"
download_and_extract "libx/libxrender" "libxrender1"
download_and_extract "libx/libxss" "libxss1"
download_and_extract "libx/libxtst" "libxtst6"
download_and_extract "libx/libxi" "libxi6"
download_and_extract "libx/libxinerama" "libxinerama1"
download_and_extract "libx/libxau" "libxau6"
download_and_extract "libx/libxdmcp" "libxdmcp6"
download_and_extract "libx/libxcb" "libxcb-shm0"
download_and_extract "libx/libxcb" "libxcb-render0"
download_and_extract "libx/libxcb" "libxcb-dri3-0"
download_and_extract "libx/libxcb" "libxcb-present0"
download_and_extract "libx/libxcb" "libxcb-sync1"
download_and_extract "libx/libxcb" "libxcb-xfixes0"
download_and_extract "libx/libxcb" "libxcb-randr0"
download_and_extract "a/avahi" "libavahi-common3"
download_and_extract "a/avahi" "libavahi-client3"
download_and_extract "f/freetype" "libfreetype6"
download_and_extract "h/harfbuzz" "libharfbuzz0b"
download_and_extract "libb/libbsd" "libbsd0"
download_and_extract "libm/libmd" "libmd0"
download_and_extract "p/pango1.0" "libpango-1.0-0"
download_and_extract "c/cairo" "libcairo2"
download_and_extract "libp/libpng1.6" "libpng16-16"
download_and_extract "b/brotli" "libbrotli1"
download_and_extract "b/bzip2" "libbz2-1.0"
download_and_extract "f/fontconfig" "fontconfig"
download_and_extract "f/fontconfig" "fontconfig-config"
download_and_extract "f/fonts-dejavu" "fonts-dejavu-core"
download_and_extract "g/graphite2" "libgraphite2-3"
download_and_extract "libt/libthai" "libthai0"
download_and_extract "f/fribidi" "libfribidi0"
download_and_extract "libd/libdatrie" "libdatrie1"
download_and_extract "libp/libpixman" "libpixman-1-0"
download_and_extract "e/expat" "libexpat1"
download_and_extract "libf/libffi" "libffi8"
download_and_extract "p/pcre2" "libpcre2-8-0"

# Fontconfig
cat > /tmp/fonts_conf/fonts.conf << 'FONTCONF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/tmp/libs/extracted/usr/share/fonts</dir>
  <cachedir>/tmp/fonts_cache</cachedir>
</fontconfig>
FONTCONF

# Install Playwright chromium if not present
export PATH="/home/agent/.node/bin:$PATH"
if [ ! -f "/home/agent/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome" ]; then
  echo "📦 安裝 Playwright Chromium..."
  npx playwright install chromium 2>&1 | tail -3
fi

echo ""
echo "✅ 環境設定完成！"
echo "測試 Chrome:"
export LD_LIBRARY_PATH="/tmp/libs/extracted/usr/lib/x86_64-linux-gnu:/tmp/libs/extracted/lib/x86_64-linux-gnu"
/home/agent/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome --version 2>/dev/null || echo "⚠️  Chrome 測試失敗，請檢查 libs"
