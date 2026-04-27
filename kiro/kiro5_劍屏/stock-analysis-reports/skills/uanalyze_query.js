#!/usr/bin/env node
/**
 * Skill: 優分析小助理完整查詢（API 直接呼叫版）
 * 使用方式: node uanalyze_query.js <股票代號> [股票名稱]
 * 例: node uanalyze_query.js 2330 台積電
 */

const { chromium } = require('/home/agent/.npm/_npx/e41f203b7505f1fb/node_modules/playwright');
const fs = require('fs');
const { execSync } = require('child_process');

const STOCK_CODE = process.argv[2] || '3533';
const STOCK_NAME = process.argv[3] || STOCK_CODE;
const REPORT_REPO = process.env.REPORT_REPO || 'MasonLee3721/agent_skills';
const REPO_LOCAL = '/tmp/agent_skills';
const REPORT_DIR = `${REPO_LOCAL}/kiro/kiro5_劍屏/stock-analysis-reports/reports`;
const CHROME = '/home/agent/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome';

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function run() {
  process.env.LD_LIBRARY_PATH = `/tmp/playwright-libs:${process.env.LD_LIBRARY_PATH || ''}`;

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
  await sleep(400);
  await page.fill('input[type="password"]', process.env.UANALYZE_PASSWORD);
  await sleep(400);
  const loginBtn = await page.$('button[type="submit"]');
  if (loginBtn) await loginBtn.click({ force: true });
  await sleep(5000);
  if (page.url().includes('login')) throw new Error('登入失敗');
  console.log('✅ 登入成功');

  // ── 用 page.evaluate 呼叫所有 API（帶 cookie）──
  console.log(`📊 查詢 ${STOCK_CODE} ${STOCK_NAME}...`);

  // 取得 Bearer token（從 cookies）
  const cookies = await context.cookies();
  const bearerToken = cookies.find(c => c.name === 'access_token')?.value || '';

  // 用 page.evaluate 呼叫所有 API
  const apiResults = await page.evaluate(async ([code, token]) => {
    const fetchApi = async (url, useBearer) => {
      const headers = {
        'Accept': 'application/json, text/plain, */*',
        'Referer': 'https://pro.uanalyze.com.tw/',
      };
      if (useBearer && token) headers['Authorization'] = `Bearer ${token}`;
      const resp = await fetch(url, { credentials: 'include', headers });
      return await resp.text();
    };
    return {
      assist: await fetchApi(`https://data.uanalyze.twobitto.com/api/assist/reports?stock=${code}`, true),
      guides: await fetchApi(`https://data.uanalyze.twobitto.com/api/guides/${code}`, true),
      eps: await fetchApi(`https://cronjob.uanalyze.com.tw/data_fetch/api/EPSRevenueConsensusEstimate/${code}`, false),
      ai: await fetchApi(`https://data.uanalyze.twobitto.com/api/ai/reports?stock=${code}&ai_model=gpt-4.1-mini`, true).catch(() => null),
    };
  }, [STOCK_CODE, bearerToken]);

  await browser.close();

  // 解析結果
  const assistData = JSON.parse(apiResults.assist);
  const assistText = assistData.data?.text || '';
  console.log(`  ✅ 小助理報告 (${assistText.length}b)`);

  const guidesData = JSON.parse(apiResults.guides);
  console.log(`  ✅ 自動導航 (${guidesData.data?.stages?.length || 0} 階段)`);

  const epsData = JSON.parse(apiResults.eps);
  console.log(`  ✅ EPS 資料 (${apiResults.eps.length}b)`);

  const aiData = apiResults.ai ? JSON.parse(apiResults.ai) : null;
  if (aiData) console.log(`  ✅ AI 評分 (${apiResults.ai.length}b)`);

  // ── 建立 Markdown 報告 ──
  console.log('📝 建立報告...');
  const today = new Date().toISOString().slice(0, 10);
  const dateStr = today.replace(/-/g, '');
  const filename = `${STOCK_NAME}(${STOCK_CODE})_${dateStr}.md`;

  let report = '';

  // 1. 自動導航
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

  // 2. EPS 預估表格
  if (epsData.data?.data) {
    const d = epsData.data.data;
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

  // 3. AI 評分
  if (aiData?.data?.scores) {
    report += `\n# ${STOCK_NAME}（${STOCK_CODE}）AI 成長股評分\n\n`;
    report += `> 資料來源：優分析 UAnalyze - AI Reports (gpt-4.1-mini)\n\n`;
    aiData.data.scores.forEach(s => {
      report += `## ${s.name}：${s.score}分\n\n`;
      (s.items || []).forEach(item => {
        report += `- **${item.reason}**`;
        if (item.detail) report += `：${item.detail}`;
        report += '\n';
      });
      report += '\n';
    });
    report += `---\n\n`;
  }

  // 4. 小助理完整分析
  report += `\n# ${STOCK_NAME}（${STOCK_CODE}）小助理完整分析報告\n\n`;
  report += `> **查詢日期**：${today}  \n`;
  report += `> **資料來源**：優分析 UAnalyze 產業資料庫 - 小助理  \n\n---\n\n`;
  report += assistText + '\n\n---\n\n';

  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const filepath = `${REPORT_DIR}/${filename}`;
  fs.writeFileSync(filepath, report);
  console.log(`✅ 報告已存：${filepath} (${(report.length/1024).toFixed(1)} KB)`);

  // ── Push 到 GitHub ──
  console.log('🚀 Push 到 GitHub...');
  const ghToken = execSync('gh auth token', { encoding: 'utf8' }).trim();
  execSync(`cd ${REPO_LOCAL} && git config user.email "kiro5@uanalyze" && git config user.name "MuJianping"`, { stdio: 'pipe' });
  execSync(`cd ${REPO_LOCAL} && git remote set-url origin "https://${ghToken}@github.com/${REPORT_REPO}.git"`, { stdio: 'pipe' });
  execSync(`cd ${REPO_LOCAL} && git pull origin main --rebase 2>/dev/null || true`, { stdio: 'pipe' });
  execSync(`cd ${REPO_LOCAL} && git add "kiro/kiro5_劍屏/stock-analysis-reports/reports/${filename}" && git commit -m "add: ${STOCK_NAME}(${STOCK_CODE}) 小助理完整分析 ${dateStr}" && git push origin main`, { stdio: 'inherit' });

  console.log(`\n🎉 完成！`);
  console.log(`📎 https://github.com/${REPORT_REPO}/blob/main/kiro/kiro5_%E5%8A%8D%E5%B1%8F/stock-analysis-reports/reports/${encodeURIComponent(filename)}`);
}

run().catch(err => { console.error('❌ Error:', err.message); process.exit(1); });
