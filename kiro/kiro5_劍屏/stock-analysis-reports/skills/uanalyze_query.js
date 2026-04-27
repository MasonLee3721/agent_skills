#!/usr/bin/env node
/**
 * Skill: 優分析小助理完整查詢
 * 功能: 登入 pro.uanalyze.com.tw，查詢指定股票的小助理所有主題 + 自動導航 + EPS預估，
 *       存成 md 檔案並 push 到 GitHub。
 *
 * 使用方式:
 *   node uanalyze_query.js <股票代號> [股票名稱]
 *   例: node uanalyze_query.js 3533 嘉澤
 *
 * 環境變數需求:
 *   UANALYZE_USERNAME  - 優分析帳號 email
 *   UANALYZE_PASSWORD  - 優分析密碼
 *   GH_TOKEN           - GitHub token (或已設定 gh CLI)
 *   REPORT_REPO        - GitHub repo (預設: MasonLee3721/stock-analysis-reports)
 *
 * 系統需求:
 *   - Node.js (位於 /home/agent/.node/bin/node)
 *   - Playwright (位於 /home/agent/.npm/_npx/e41f203b7505f1fb/node_modules/playwright)
 *   - Chrome binary (/home/agent/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome)
 *   - 系統 libs (/tmp/libs/extracted) — 見 setup() 函數
 *   - gh CLI 已登入
 */

const { chromium } = require('/home/agent/.npm/_npx/e41f203b7505f1fb/node_modules/playwright');
const fs = require('fs');
const { execSync } = require('child_process');

// ── 設定 ──────────────────────────────────────────────────────────────────
const STOCK_CODE = process.argv[2] || '3533';
const STOCK_NAME = process.argv[3] || STOCK_CODE;
const REPORT_REPO = process.env.REPORT_REPO || 'MasonLee3721/stock-analysis-reports';
const REPO_LOCAL = '/tmp/stock-analysis-reports';
const REPORT_DIR = `${REPO_LOCAL}/kiro5_劍屏/reports`;
const CHROME = '/home/agent/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome';
const PLAYWRIGHT = '/home/agent/.npm/_npx/e41f203b7505f1fb/node_modules/playwright';

const TOPICS = [
  '近況發展','產業趨勢','產品線分析','長短期展望','供需分析',
  '觀察重點','利多因素','利空因素','接單狀況','資本支出',
  '新產品','時間表','相關公司','同業競爭','護城河分析',
  '併購分析','重要數字','公司概覽','銷售地區'
];

// ── 環境設定 ──────────────────────────────────────────────────────────────
function setupEnv() {
  const libDir = '/tmp/libs/extracted/usr/lib/x86_64-linux-gnu';
  const lib2Dir = '/tmp/libs/extracted/lib/x86_64-linux-gnu';
  process.env.LD_LIBRARY_PATH = `${libDir}:${lib2Dir}:${process.env.LD_LIBRARY_PATH || ''}`;
  process.env.FONTCONFIG_FILE = '/tmp/fonts_conf/fonts.conf';
}

// ── 解析 API 回應 ─────────────────────────────────────────────────────────
function parseContent(rawStr) {
  try {
    const p = JSON.parse(rawStr);
    if (p.data?.text) return p.data.text;
    if (p.text?.answer) return p.text.answer;
    if (typeof p.text === 'string') return p.text;
    return rawStr;
  } catch(e) { return rawStr; }
}

// ── 主流程 ────────────────────────────────────────────────────────────────
async function run() {
  setupEnv();

  const browser = await chromium.launch({
    headless: true,
    executablePath: CHROME,
    args: ['--no-sandbox','--disable-setuid-sandbox','--disable-dev-shm-usage','--disable-gpu','--no-zygote']
  });

  const context = await browser.newContext();
  const page = await context.newPage();
  await page.setViewportSize({ width: 1280, height: 900 });

  // CDP 攔截所有 API 回應
  const client = await context.newCDPSession(page);
  await client.send('Network.enable');
  const pending = {};
  const captured = {
    guides: null,
    eps: null,
    completions: {}
  };

  client.on('Network.responseReceived', e => {
    const url = e.response.url;
    if (url.includes('twobitto') || url.includes('cronjob') || url.includes('api.uanalyze')) {
      pending[e.requestId] = url;
    }
  });

  client.on('Network.loadingFinished', async e => {
    if (!pending[e.requestId]) return;
    try {
      const b = await client.send('Network.getResponseBody', { requestId: e.requestId });
      const text = b.base64Encoded ? Buffer.from(b.body, 'base64').toString() : b.body;
      const url = pending[e.requestId];

      if (url.includes('twobitto/api/guides')) {
        captured.guides = text;
        console.log(`  ✅ guides (${text.length}b)`);
      } else if (url.includes('EPSRevenueConsensusEstimate')) {
        captured.eps = text;
        console.log(`  ✅ EPS data (${text.length}b)`);
      } else if (url.includes('completions')) {
        const match = url.match(/prompt=([^&]+)/);
        const key = match ? decodeURIComponent(match[1]) : url;
        captured.completions[key] = text;
        console.log(`  ✅ ${key} (${text.length}b)`);
      }
    } catch(e) {}
  });

  // ── 登入 ──
  console.log('🔐 登入中...');
  await page.goto('https://pro.uanalyze.com.tw/login-page', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);
  await page.fill('input[type="email"]', process.env.UANALYZE_USERNAME);
  await page.fill('input[type="password"]', process.env.UANALYZE_PASSWORD);
  await page.press('input[type="password"]', 'Enter');
  await page.waitForTimeout(5000);
  console.log('✅ 登入成功');

  // ── 進入產業資料庫 ──
  await page.goto('https://pro.uanalyze.com.tw/lab/dashboard/lynch-tengrower', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);

  // 關閉彈窗
  await page.evaluate(() => {
    document.querySelectorAll('.modal-backdrop,.modal,.new-version').forEach(el => el.remove());
    document.body.classList.remove('modal-open');
    Array.from(document.querySelectorAll('button')).forEach(b => { if(b.textContent.includes('我知道了')) b.click(); });
  });

  // ── 搜尋股票 ──
  console.log(`🔍 搜尋 ${STOCK_CODE}...`);
  const input = await page.$('input[placeholder*="股票"]');
  await input.click({ force: true });
  await input.fill(STOCK_CODE);
  await page.waitForTimeout(1000);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(6000);
  // guides API 在這裡觸發

  // ── 進入小助理 ──
  console.log('📋 進入小助理...');
  await page.locator('text=小助理').first().click({ force: true });
  await page.waitForTimeout(4000);
  // EPS consensus API 在這裡觸發

  await page.evaluate(() => {
    Array.from(document.querySelectorAll('button')).forEach(b => { if(b.textContent.includes('我知道了')) b.click(); });
  });
  await page.waitForTimeout(500);

  // ── 逐一點擊主題按鈕 ──
  console.log('🔘 查詢所有主題...');
  for (const topic of TOPICS) {
    await page.evaluate((t) => {
      const target = Array.from(document.querySelectorAll('*')).find(el =>
        el.children.length === 0 &&
        (el.textContent.trim() === t || el.textContent.trim() === `❤️${t}`) &&
        el.getBoundingClientRect().width > 30 &&
        el.getBoundingClientRect().top > 100
      );
      if (target) target.click();
    }, topic);
    await page.waitForTimeout(8000);
  }

  await browser.close();
  console.log(`\n📊 已取得 ${Object.keys(captured.completions).length} 個主題`);

  // ── 建立 Markdown 報告 ──
  console.log('📝 建立報告...');
  const today = new Date().toISOString().slice(0, 10);
  const dateStr = today.replace(/-/g, '');
  const filename = `${STOCK_NAME}(${STOCK_CODE})_${dateStr}.md`;
  const filepath = `${REPORT_DIR}/${filename}`;

  let report = '';

  // 1. 自動導航
  if (captured.guides) {
    const guidesData = JSON.parse(captured.guides);
    report += `# ${STOCK_NAME}（${STOCK_CODE}）自動導航\n\n`;
    report += `> 資料來源：優分析 UAnalyze 產業資料庫 - 自動導航\n\n---\n\n`;
    guidesData.data.stages.forEach(stage => {
      report += `## ${stage.name}\n\n`;
      stage.steps.forEach(step => {
        report += `### STEP：${step.name}\n\n`;
        if (step.metadata?.ref) {
          step.metadata.ref.forEach(r => { if (r.content) report += r.content + '\n\n'; });
        }
        if (step.metadata?.why) report += `> **為什麼看這個？** ${step.metadata.why}\n\n`;
        if (step.metadata?.guide) report += `> **指引：** ${step.metadata.guide}\n\n`;
      });
      report += `---\n\n`;
    });
  }

  // 2. EPS 預估表格
  if (captured.eps) {
    const epsData = JSON.parse(captured.eps).data.data;
    const rev = epsData['ua50189_cp']?.Data || {};
    const eps = epsData['ua50187_cp']?.Data || {};
    const coreEps = epsData['ua50209_cp']?.Data || {};

    report += `\n# ${STOCK_NAME}（${STOCK_CODE}）法人預估 EPS & 營收共識統計\n\n`;
    report += `> 資料來源：優分析 UAnalyze - EPSRevenueConsensusEstimate  \n`;
    report += `> 單位：營收（百萬元）、EPS（元）\n\n`;
    report += `| 年度 | 法人平均預估營收（百萬元） | 法人平均預估EPS（元） | 法人平均預估本業EPS（元） |\n`;
    report += `|------|:---:|:---:|:---:|\n`;
    Object.keys(rev).filter(y => parseInt(y) >= 2022 || y.includes('(f)')).forEach(year => {
      const label = year.includes('(f)') ? `**${year}**` : year;
      report += `| ${label} | ${rev[year] ?? '-'} | ${eps[year] ?? '-'} | ${coreEps[year] ?? '-'} |\n`;
    });
    report += `\n> **(f) = 法人預估值**\n\n---\n\n`;
  }

  // 3. 小助理各主題
  report += `\n# ${STOCK_NAME}（${STOCK_CODE}）小助理完整分析報告\n\n`;
  report += `> **查詢日期**：${today}  \n`;
  report += `> **資料來源**：優分析 UAnalyze 產業資料庫 - 小助理  \n\n---\n\n`;

  TOPICS.forEach((topic, i) => {
    const key = Object.keys(captured.completions).find(k => k.includes(topic.replace('❤️','')));
    report += `## ${i+1}. ${topic}\n\n`;
    if (!key) { report += `> 無相關資料\n\n---\n\n`; return; }
    const content = parseContent(captured.completions[key]);
    if (!content || content.includes('無相關資料')) { report += `> 無相關資料\n\n---\n\n`; return; }
    report += content + '\n\n---\n\n';
  });

  fs.mkdirSync(REPORT_DIR, { recursive: true });
  fs.writeFileSync(filepath, report);
  console.log(`✅ 報告已存：${filepath} (${(report.length/1024).toFixed(1)} KB)`);

  // ── Push 到 GitHub ──
  console.log('🚀 Push 到 GitHub...');
  const token = execSync('gh auth token', { encoding: 'utf8' }).trim();
  execSync(`cd ${REPO_LOCAL} && git config user.email "kiro5@uanalyze" && git config user.name "MuJianping"`, { stdio: 'pipe' });
  execSync(`cd ${REPO_LOCAL} && git remote set-url origin "https://${token}@github.com/${REPORT_REPO}.git"`, { stdio: 'pipe' });
  execSync(`cd ${REPO_LOCAL} && git add "kiro5_劍屏/reports/${filename}" && git commit -m "add: ${STOCK_NAME}(${STOCK_CODE}) 小助理完整分析 ${dateStr}" && git push origin main`, { stdio: 'inherit' });

  console.log(`\n🎉 完成！`);
  console.log(`📎 GitHub: https://github.com/${REPORT_REPO}/blob/main/${encodeURIComponent(filename)}`);
}

run().catch(err => { console.error('❌ Error:', err.message); process.exit(1); });
