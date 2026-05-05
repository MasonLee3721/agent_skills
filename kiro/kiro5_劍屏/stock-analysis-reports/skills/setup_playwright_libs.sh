#!/bin/bash
# setup_playwright_libs.sh
# 下載 Playwright Chrome 所需的 Debian bookworm shared libraries
# 存到持久化路徑 /home/agent/playwright-libs（pod 重啟不消失）
# 已存在就跳過，不重複下載

LIBDIR="/home/agent/playwright-libs"
BASE="https://ftp.debian.org/debian/pool/main"

# 已存在就跳過
if [ -f "$LIBDIR/usr/lib/x86_64-linux-gnu/libglib-2.0.so.0" ]; then
  echo "✅ playwright-libs 已存在，跳過下載"
  exit 0
fi

echo "📦 下載 Playwright libs 到 $LIBDIR ..."
mkdir -p "$LIBDIR"
TMP=$(mktemp -d)

dl() {
  local name=$1 url=$2
  echo -n "  $name... "
  curl -fsSL "$url" -o "$TMP/${name}.deb" 2>/dev/null \
    && dpkg -x "$TMP/${name}.deb" "$LIBDIR" 2>/dev/null \
    && echo "✅" || echo "❌"
}

# 固定 bookworm (Debian 12) 版本號，不動態抓
# 注意：URL 中不用 %3a 編碼，直接用實際檔名
dl libglib2.0-0    "$BASE/g/glib2.0/libglib2.0-0_2.74.6-2+deb12u9_amd64.deb"
dl libnss3         "$BASE/n/nss/libnss3_3.87.1-1+deb12u2_amd64.deb"
dl libnspr4        "$BASE/n/nspr/libnspr4_4.35-1_amd64.deb"
dl libdbus-1-3     "$BASE/d/dbus/libdbus-1-3_1.14.10-1~deb12u1_amd64.deb"
dl libatk1.0-0     "$BASE/a/atk1.0/libatk1.0-0_2.36.0-2_amd64.deb"
dl libatk-bridge   "$BASE/a/at-spi2-core/libatk-bridge2.0-0_2.46.0-5_amd64.deb"
dl libatspi2       "$BASE/a/at-spi2-core/libatspi2.0-0_2.46.0-5_amd64.deb"
dl libcups2        "$BASE/c/cups/libcups2_2.4.2-3+deb12u9_amd64.deb"
dl libdrm2         "$BASE/libd/libdrm/libdrm2_2.4.114-1+b1_amd64.deb"
dl libgbm1         "$BASE/m/mesa/libgbm1_22.3.6-1+deb12u1_amd64.deb"
dl libasound2      "$BASE/a/alsa-lib/libasound2_1.2.8-1+b1_amd64.deb"
dl libxkbcommon0   "$BASE/libx/libxkbcommon/libxkbcommon0_1.5.0-1_amd64.deb"
dl libxcomposite1  "$BASE/libx/libxcomposite/libxcomposite1_0.4.6-1+b2_amd64.deb"
dl libxdamage1     "$BASE/libx/libxdamage/libxdamage1_1.1.6-1+b2_amd64.deb"
dl libxfixes3      "$BASE/libx/libxfixes/libxfixes3_6.0.0-2+b4_amd64.deb"
dl libxrandr2      "$BASE/libx/libxrandr/libxrandr2_1.5.2-2+b1_amd64.deb"
dl libx11-6        "$BASE/libx/libx11/libx11-6_1.8.4-2+deb12u2_amd64.deb"
dl libxext6        "$BASE/libx/libxext/libxext6_1.3.4-1+b1_amd64.deb"
dl libxcb1         "$BASE/libx/libxcb/libxcb1_1.15-1_amd64.deb"
dl libxcb-shm0     "$BASE/libx/libxcb/libxcb-shm0_1.15-1_amd64.deb"
dl libxcb-render0  "$BASE/libx/libxcb/libxcb-render0_1.15-1_amd64.deb"
dl libxau6         "$BASE/libx/libxau/libxau6_1.0.11-1_amd64.deb"
dl libxdmcp6       "$BASE/libx/libxdmcp/libxdmcp6_1.1.5-1_amd64.deb"
dl libxrender1     "$BASE/libx/libxrender/libxrender1_0.9.10-1_amd64.deb"
dl libxi6          "$BASE/libx/libxi/libxi6_1.8-1+b1_amd64.deb"
dl libsqlite3-0    "$BASE/s/sqlite3/libsqlite3-0_3.40.1-2+deb12u2_amd64.deb"
dl libavahi-common "$BASE/a/avahi/libavahi-common3_0.8-10+deb12u1_amd64.deb"
dl libavahi-client "$BASE/a/avahi/libavahi-client3_0.8-10+deb12u1_amd64.deb"
dl libwayland-srv  "$BASE/w/wayland/libwayland-server0_1.21.0-1_amd64.deb"
dl libcairo2       "$BASE/c/cairo/libcairo2_1.16.0-7_amd64.deb"
dl libpango        "$BASE/p/pango1.0/libpango-1.0-0_1.50.12+ds-1_amd64.deb"
dl libpixman       "$BASE/p/pixman/libpixman-1-0_0.42.2-1_amd64.deb"
dl libpng16        "$BASE/libp/libpng1.6/libpng16-16_1.6.39-2+deb12u1_amd64.deb"
dl libfreetype6    "$BASE/f/freetype/libfreetype6_2.12.1+dfsg-5+deb12u4_amd64.deb"
dl libfontconfig1  "$BASE/f/fontconfig/libfontconfig1_2.14.1-4_amd64.deb"
dl libfribidi0     "$BASE/f/fribidi/libfribidi0_1.0.16-5+b1_amd64.deb"
dl libthai0        "$BASE/libt/libthai/libthai0_0.1.29-1_amd64.deb"
dl libdatrie1      "$BASE/libd/libdatrie/libdatrie1_0.2.13-1_amd64.deb"
dl libgraphite2    "$BASE/g/graphite2/libgraphite2-3_1.3.14-1_amd64.deb"
# harfbuzz: 必須用 6.0.0，新版需要 GLIBC_2.38 且與 pango 1.50 不相容
dl libharfbuzz0b   "$BASE/h/harfbuzz/libharfbuzz0b_6.0.0+dfsg-3_amd64.deb"

rm -rf "$TMP"
echo "✅ 完成：$LIBDIR"
