#!/usr/bin/env node
/**
 * Skill: 優分析小助理完整查詢
 * 使用方式: node uanalyze_query.js <股票代號> [股票名稱]
 * 例: node uanalyze_query.js 2303 聯電
 *
 * version: 2.0.0
 * updated: 2026-04-28
 * changelog:
 *   v2.0.0 - 改用 POST completions API 直接呼叫，不再導航到小助理頁面
 *            （/38364 在 headless 環境下會 crash）
 *            正確 API: POST https://data.uanalyze.twobitto.com/completions
 *            需帶 Authorization: Bearer <access_token>
 *   v1.0.0 - 原版 CDP 攔截 + 主題點擊（已廢棄）
 */

const { chromium } = require('/tmp/agent_skills/kiro/kiro5_劍屏/stock-analysis-reports/skills/node_modules/playwright');
const fs = require('fs');
const { execSync } = require('child_process');

const STOCK_CODE = process.argv[2] || '3533';
const STOCK_NAME = process.argv[3] || STOCK_CODE;
const REPORT_REPO = process.env.REPORT_REPO || 'MasonLee3721/agent_skills';
const REPO_LOCAL = '/tmp/agent_skills';
const REPORT_DIR = `${REPO_LOCAL}/kiro/kiro5_劍屏/stock-analysis-reports/reports`;
const CHROME = '/home/agent/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome';
const AI_HOST = 'https://data.uanalyze.twobitto.com';

const TOPICS = [
  '近況發展','產業趨勢','產品線分析','長短期展望','供需分析',
  '觀察重點','利多因素','利空因素','接單狀況','資本支出',
  '時間表','同業競爭','護城河分析','重要數字','公司概覽','銷售地區','併購分析'
];

const sleep = ms => new Promise(r => setTimeout(r, ms));
const rand = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;

function parseContent(rawStr) {
  try {
    const p = JSON.parse(rawStr);
    if (p.data?.text) return p.data.text;
    if (p.text?.answer) return p.text.answer;
    if (typeof p.text === 'string') return p.text;
    return rawStr;
  } catch(e) { return rawStr; }
}

async function run() {
  // 自動安裝 Playwright libs（持久化路徑，pod 重啟不消失）
  try {
    execSync('bash /home/agent/scripts/setup_playwright_libs.sh', { stdio: 'inherit' });
  } catch(e) {
    console.error('⚠️  setup_playwright_libs.sh 執行失敗:', e.message);
  }
  
  process.env.LD_LIBRARY_PATH = `/home/agent/playwright-libs/usr/lib/x86_64-linux-gnu:/home/agent/playwright-libs/lib/x86_64-linux-gnu:/home/agent/playwright-libs/usr/lib:${process.env.LD_LIBRARY_PATH || ''}`;

  const browser = await chromium.launch({
    headless: true,
    executablePath: CHROME,
    args: ['--no-sandbox','--disable-setuid-sandbox','--disable-dev-shm-usage','--disable-gpu','--headless=new','--disable-blink-features=AutomationControlled'],
  });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    locale: 'zh-TW',
    timezoneId: 'Asia/Taipei',
  });
  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3,4,5] });
    window.chrome = { runtime: {} };
  });
  const page = await context.newPage();
  await page.setViewportSize({ width: 1280, height: 900 });

  // ── 登入 ──
  console.log('🔐 登入中...');
  await page.goto('https://pro.uanalyze.com.tw/login-page', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(3000);
  await page.evaluate(() => {
    document.querySelectorAll('.modal-backdrop,.modal,.new-version').forEach(el => el.remove());
    document.body.classList.remove('modal-open');
  });
  await sleep(300);
  await page.fill('input[type="email"]', process.env.UANALYZE_USERNAME);
  await sleep(rand(60, 150));
  await page.fill('input[type="password"]', process.env.UANALYZE_PASSWORD);
  await sleep(rand(60, 150));
  const loginBtn = await page.$('button[type="submit"]');
  if (loginBtn) await loginBtn.click({ force: true });
  await sleep(5000);
  if (page.url().includes('login')) throw new Error('登入失敗');
  console.log('✅ 登入成功');

  // ── 取得 access_token（登入後即可取得，不需導航到 dashboard）──
  const cookies = await context.cookies();
  const accessToken = cookies.find(c => c.name === 'access_token')?.value;
  const tokenType = cookies.find(c => c.name === 'token_type')?.value || 'Bearer';
  if (!accessToken) throw new Error('找不到 access_token，請確認登入成功');
  console.log('✅ 取得 access_token');

  await browser.close();

  // ── 用 Node.js fetch 直接呼叫 API（避免 browser 在重型 SPA 頁面 crash）──
  const nodeGet = async (url) => {
    const resp = await fetch(url, {
      headers: { 'Authorization': `${tokenType} ${accessToken}` }
    });
    return await resp.text();
  };

  // guides + EPS（直接 API，不需 CDP 攔截）
  const captured = { guides: null, eps: null };
  try {
    captured.guides = await nodeGet(`https://data.uanalyze.twobitto.com/api/guides/${STOCK_CODE}`);
    console.log(`  ✅ guides (${captured.guides.length}b)`);
  } catch(e) { console.log('  ❌ guides:', e.message); }
  try {
    captured.eps = await nodeGet(`https://cronjob.uanalyze.com.tw/data_fetch/api/EPSRevenueConsensusEstimate/${STOCK_CODE}`);
    console.log(`  ✅ EPS data (${captured.eps.length}b)`);
  } catch(e) { console.log('  ❌ EPS:', e.message); }

  // ── 直接 POST completions API 取得每個主題 ──
  console.log('📋 查詢小助理主題...');
  const completions = {};

  for (const topic of TOPICS) {
    process.stdout.write(`  查詢「${topic}」...`);
    try {
      const body = `prompt=${encodeURIComponent(topic)}&stock=${STOCK_CODE}`;
      const resp = await fetch(`${AI_HOST}/completions?prompt=${encodeURIComponent(topic)}&stock=${STOCK_CODE}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': `${tokenType} ${accessToken}`,
          'Accept': 'application/json',
          'Referer': 'https://pro.uanalyze.com.tw/',
        },
        body
      });
      const text = await resp.text();
      if (resp.status === 200) {
        completions[topic] = parseContent(text);
        console.log(` ✅ (${text.length}b)`);
      } else {
        console.log(` ❌ status ${resp.status}`);
      }
    } catch(e) {
      console.log(` ❌ ${e.message}`);
    }
    await sleep(rand(1000, 2000));
  }
  console.log(`\n📊 已取得 ${Object.keys(completions).length}/${TOPICS.length} 個主題`);

  // ── 建立 Markdown 報告 ──
  console.log('📝 建立報告...');
  const today = new Date().toISOString().slice(0, 10);
  const dateStr = today.replace(/-/g, '');
  const filename = `${STOCK_NAME}(${STOCK_CODE})_${dateStr}.md`;

  let report = '';

  // 1. 自動導航
  if (captured.guides) {
    try {
      const guidesData = JSON.parse(captured.guides);
      if (guidesData.data?.stages?.length > 0) {
        report += `# ${STOCK_NAME}（${STOCK_CODE}）自動導航\n\n`;
        report += `> 資料來源：優分析 UAnalyze 產業資料庫 - 自動導航\n\n---\n\n`;
        guidesData.data.stages.forEach(stage => {
          report += `## ${stage.name}\n\n`;
          (stage.steps || []).forEach(step => {
            report += `### STEP：${step.name}\n\n`;
            if (step.metadata?.ref) step.metadata.ref.forEach(r => { if (r.content) report += r.content + '\n\n'; });
            if (step.metadata?.why) report += `> **為什麼看這個？** ${step.metadata.why}\n\n`;
            if (step.metadata?.guide) report += `> **指引：** ${step.metadata.guide}\n\n`;
          });
          report += `---\n\n`;
        });
      }
    } catch(e) { console.log('guides parse error:', e.message); }
  }

  // 2. EPS 預估表格
  if (captured.eps) {
    try {
      const epsData = JSON.parse(captured.eps);
      const d = epsData.data?.data;
      if (d) {
        const rev = d['ua50189_cp']?.Data || {};
        const eps = d['ua50187_cp']?.Data || {};
        const coreEps = d['ua50209_cp']?.Data || {};
        if (Object.keys(rev).length > 0) {
          report += `\n# ${STOCK_NAME}（${STOCK_CODE}）法人預估 EPS & 營收共識統計\n\n`;
          report += `> 資料來源：優分析 UAnalyze - EPSRevenueConsensusEstimate  \n`;
          report += `> 單位：營收（百萬元）、EPS（元）\n\n`;
          report += `| 年度 | 法人平均預估營收（百萬元） | 法人平均預估EPS（元） | 法人平均預估本業EPS（元） |\n`;
          report += `|------|:---:|:---:|:---:|\n`;
          Object.keys(rev).forEach(year => {
            const label = year.includes('(f)') ? `**${year}**` : year;
            report += `| ${label} | ${rev[year] ?? '-'} | ${eps[year] ?? '-'} | ${coreEps[year] ?? '-'} |\n`;
          });
          report += `\n> **(f) = 法人預估值**\n\n---\n\n`;
        }
      }
    } catch(e) { console.log('eps parse error:', e.message); }
  }

  // 3. 小助理各主題
  report += `\n# ${STOCK_NAME}（${STOCK_CODE}）小助理完整分析報告\n\n`;
  report += `> **查詢日期**：${today}  \n`;
  report += `> **資料來源**：優分析 UAnalyze 產業資料庫 - 小助理  \n`;
  report += `> **股票**：${STOCK_CODE} ${STOCK_NAME}\n\n---\n\n`;

  // 目錄
  report += `## 目錄\n\n`;
  TOPICS.forEach((topic, i) => { report += `${i+1}. [${topic}](#${i+1})\n`; });
  report += `\n---\n\n`;

  TOPICS.forEach((topic, i) => {
    report += `## ${i+1}. ${topic}\n\n`;
    const content = completions[topic];
    if (!content) { report += `> 無相關資料\n\n---\n\n`; return; }
    report += content + '\n\n---\n\n';
  });

  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const filepath = `${REPORT_DIR}/${filename}`;
  fs.writeFileSync(filepath, report);
  console.log(`✅ 報告已存：${filepath} (${(report.length/1024).toFixed(1)} KB)`);

  // ── Push 到 GitHub ──
  console.log('🚀 Push 到 GitHub...');
  // 先 clone 或 pull repo
  if (!fs.existsSync(REPO_LOCAL)) {
    const ghToken = execSync('gh auth token', { encoding: 'utf8' }).trim();
    execSync(`git clone "https://${ghToken}@github.com/${REPORT_REPO}.git" ${REPO_LOCAL}`, { stdio: 'pipe' });
  }
  const ghToken = execSync('gh auth token', { encoding: 'utf8' }).trim();
  execSync(`cd ${REPO_LOCAL} && git config user.email "kiro5@uanalyze" && git config user.name "MuJianping"`, { stdio: 'pipe' });
  execSync(`cd ${REPO_LOCAL} && git remote set-url origin "https://${ghToken}@github.com/${REPORT_REPO}.git"`, { stdio: 'pipe' });
  execSync(`cd ${REPO_LOCAL} && git pull origin main --rebase 2>/dev/null || true`, { stdio: 'pipe' });

  // 複製報告到 repo
  const repoReportDir = `${REPO_LOCAL}/kiro/kiro5_劍屏/stock-analysis-reports/reports`;
  fs.mkdirSync(repoReportDir, { recursive: true });
  fs.copyFileSync(filepath, `${repoReportDir}/${filename}`);

  execSync(`cd ${REPO_LOCAL} && git add "kiro/kiro5_劍屏/stock-analysis-reports/reports/${filename}" && git commit -m "add: ${STOCK_NAME}(${STOCK_CODE}) 小助理完整分析 ${dateStr}" && git push origin main`, { stdio: 'inherit' });

  console.log(`\n🎉 完成！`);
  console.log(`📎 https://github.com/${REPORT_REPO}/blob/main/kiro/kiro5_%E5%8A%8D%E5%B1%8F/stock-analysis-reports/reports/${encodeURIComponent(filename)}`);
}

run().catch(err => { console.error('❌ Error:', err.message); process.exit(1); });
