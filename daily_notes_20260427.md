# Daily Notes — 2026-04-27

## 1. kiro5 pod 無回應

**問題：** kiro5 Discord bot 沒有回應。

**診斷：**
- Pod 狀態 `Running`，但 log 只有 10 行，最後一筆停在 `12:36:22`
- `kubectl exec ... ps aux` 發現 PID 758/759 是一個 Python polling loop
- 腳本每 60 秒呼叫 `api.uanalyze.com.tw/user/orders`，等待 `check_paid == 1`，最多 10 次（10 分鐘）
- kiro-cli-chat (PID 17) 被這個 tool call 卡住，無法回應任何新訊息

**解法：** `kubectl exec ... kill 758 759` 直接殺掉 stuck process，agent 立即恢復。

---

## 2. Playwright 無法在 pod 內啟動

**問題：** kiro5 寫了一個用 Playwright + CDP 查詢優分析的 skill，但 Chrome 無法啟動。

### 陷阱一：apt-get 沒有 root
- pod 的 user 是 `agent`（UID 1000），沒有 sudo
- `apt-get install` 直接失敗：`Permission denied`

### 陷阱二：setup_env.sh 下載 .deb 解壓縮的方式
- 原本的 `setup_env.sh` 從 Debian mirror 下載 `.deb` 解壓到 `/tmp/libs/extracted`，再設 `LD_LIBRARY_PATH`
- 問題：mirror 上同時有 Debian 11/12/13 的套件，`sort -V | head -1` 或 `tail -1` 都可能抓到錯誤版本
- Container 是 **Debian 12 (bookworm)，glibc 2.36**，但抓到的套件要求 `GLIBC_2.38` → ABI 不相容，Chrome 仍然無法啟動

### 陷阱三：snapshot mirror 不可達
- 嘗試用 `snapshot.debian.org` 固定 bookworm 時間點，但 pod 內無法連到該 mirror（全部 404）

### 最終解法：init container
- 在 k3s deployment 加一個 init container，使用 `debian:12-slim` image，以 root 執行 `apt-get install`
- 將安裝好的 libs 複製到 `/tmp/playwright-libs`（emptyDir volume，主容器可讀）
- 主容器啟動時設 `LD_LIBRARY_PATH=/tmp/playwright-libs` 即可

```bash
kubectl patch deployment agent-broker-openab-kiro5 -n agent-broker --type=json -p='[{
  "op": "add",
  "path": "/spec/template/spec/initContainers",
  "value": [{
    "name": "install-playwright-deps",
    "image": "debian:12-slim",
    "command": ["bash", "-c", "apt-get update -qq && apt-get install -y -qq --no-install-recommends libglib2.0-0 libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libasound2 libdbus-1-3 libx11-6 libxcb1 libxext6 libfontconfig1 libxss1 libxtst6 libxi6 libxrender1 libcairo2 libpango-1.0-0 libatspi2.0-0 libwayland-client0 libatomic1 && cp -r /usr/lib/x86_64-linux-gnu/. /tmp/playwright-libs/ && cp -r /lib/x86_64-linux-gnu/. /tmp/playwright-libs/ && echo done"],
    "securityContext": { "runAsUser": 0, "runAsNonRoot": false },
    "volumeMounts": [{ "name": "tmp", "mountPath": "/tmp" }]
  }]
}]'
```

**驗證：** `chrome --version` 回傳 `Google Chrome for Testing 147.0.7727.15` ✅

---

## 3. uanalyze_query.js 改善

**問題：** 原本的 skill 有多個 bot 特徵 + 路徑寫死。

**改動（已 push 到 GitHub）：**
- `setup_env.sh`：移除複雜的 .deb 下載邏輯，改為只安裝 Playwright Chromium binary（libs 由 init container 提供）
- `uanalyze_query.js`：
  - `LD_LIBRARY_PATH` 改為 `/tmp/playwright-libs`
  - 加 `--headless=new`、`--disable-blink-features=AutomationControlled`
  - `addInitScript` 隱藏 `navigator.webdriver`、偽造 `navigator.plugins`、注入 `window.chrome`
  - 真實 User-Agent、locale `zh-TW`、timezone `Asia/Taipei`
  - 登入改用逐字輸入（`keyboard.type` with random delay 60~150ms）
  - 所有 `waitForTimeout(fixed)` 改為 `sleep(rand(min, max))`

---

## 關鍵教訓

| 陷阱 | 根本原因 | 正確做法 |
|------|----------|----------|
| apt-get 失敗 | pod 無 root | 用 init container 以 root 安裝 |
| .deb 版本衝突 | mirror 混有多個 Debian 版本 | 用 init container 直接 apt-get，版本自動對齊 |
| snapshot mirror 不可達 | 網路限制 | 改用 init container，不依賴外部 mirror |
| Chrome 啟動失敗 | libs 缺失或版本不符 | init container 確保 libs 在 pod 啟動前就位 |
| Agent 卡住無回應 | tool call 內有長時間 sleep loop | 監控 ps aux，必要時 kill stuck subprocess |
