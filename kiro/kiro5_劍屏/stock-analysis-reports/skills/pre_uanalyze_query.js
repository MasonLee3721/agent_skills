#!/usr/bin/env node
/**
 * Skill: 優分析自動導航完整查詢（新手5步驟 + 進階6~10 + 深度11~20）
 * 使用方式: node pre_uanalyze_query.js <股票代號> [股票名稱]
 * 例: node pre_uanalyze_query.js 3533 嘉澤
 *
 * version: 1.1.0
 * updated: 2026-04-28
 * changelog:
 *   v1.1.0 - 新增圖表數據：股票分類評分、月營收YoY、EPS上下修趨勢、
 *            資本支出比重、關鍵發展（assist）
 *   v1.0.0 - 從 guides API 抓取自動導航完整內容（含 EPS 共識統計）
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
const rand = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;

async function run() {
  process.env.LD_LIBRARY_PATH = `/tmp/playwright-libs:${process.env.LD_LIBRARY_PATH || ''}`;

  const browser = await chromium.launch({
    headless: true, executablePath: CHROME,
    args: ['--no-sandbox','--disable-setuid-sandbox','--disable-dev-shm-usage','--disable-gpu','--headless=new','--disable-blink-features=AutomationControlled'],
  });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    locale: 'zh-TW', timezoneId: 'Asia/Taipei',
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
  await page.fill('input[type="email"]', process.env.UANALYZE_USERNAME);
  await sleep(rand(60, 150));
  await page.fill('input[type="password"]', process.env.UANALYZE_PASSWORD);
  await sleep(rand(60, 150));
  await page.click('button[type="submit"]', { force: true });
  await sleep(5000);
  if (page.url().includes('login')) throw new Error('登入失敗');
  console.log('✅ 登入成功');

  // ── 進入頁面取得 token ──
  await page.goto('https://pro.uanalyze.com.tw/lab/dashboard/lynch-tengrower/EnterpriseInsight', {
    waitUntil: 'domcontentloaded', timeout: 30000
  });
  await sleep(3000);

  const cookies = await context.cookies();
  const accessToken = cookies.find(c => c.name === 'access_token')?.value;
  const tokenType = cookies.find(c => c.name === 'token_type')?.value || 'Bearer';
  if (!accessToken) throw new Error('找不到 access_token');
  console.log('✅ 取得 access_token');

  // ── 呼叫所有 API ──
  console.log(`📋 查詢 ${STOCK_CODE} 資料...`);
  const apiData = await page.evaluate(async ([stock, token, tokenType]) => {
    const get = async (url) => {
      const resp = await fetch(url, {
        credentials: 'include',
        headers: { 'Authorization': `${tokenType} ${token}` }
      });
      return await resp.text();
    };
    return {
      guides:   await get(`https://data.uanalyze.twobitto.com/api/guides/${stock}`),
      eps:      await get(`https://cronjob.uanalyze.com.tw/data_fetch/api/EPSRevenueConsensusEstimate/${stock}`),
      ai:       await get(`https://data.uanalyze.twobitto.com/api/ai/reports?stock=${stock}&ai_model=gpt-4.1-mini`),
      monthly:  await get(`https://cronjob.uanalyze.com.tw/data_fetch/api/MonthlyRevenueAndYoY/${stock}`),
      epsHist:  await get(`https://cronjob.uanalyze.com.tw/data_fetch/api/HustoricalForecastEPS_Value_Yearly/${stock}`),
      capex:    await get(`https://cronjob.uanalyze.com.tw/data_fetch/api/CapexToSalesRatio/${stock}`),
      assist:   await get(`https://data.uanalyze.twobitto.com/api/assist/reports?stock=${stock}`),
    };
  }, [STOCK_CODE, accessToken, tokenType]);

  await browser.close();

  // ── 解析各 API ──
  const guidesData = JSON.parse(apiData.guides);
  const stages = guidesData.data?.stages || [];
  console.log(`✅ 自動導航：${stages.length} 個階段，共 ${stages.reduce((n, s) => n + s.steps.length, 0)} 個 STEP`);

  const epsData   = JSON.parse(apiData.eps);
  const aiData    = JSON.parse(apiData.ai);
  const monthly   = JSON.parse(apiData.monthly);
  const epsHist   = JSON.parse(apiData.epsHist);
  const capex     = JSON.parse(apiData.capex);
  const assist    = JSON.parse(apiData.assist);

  // ── 建立 Markdown 報告 ──
  console.log('📝 建立報告...');
  const today = new Date().toISOString().slice(0, 10);
  const dateStr = today.replace(/-/g, '');
  const filename = `${STOCK_NAME}(${STOCK_CODE})_pre_${dateStr}.md`;

  let report = `# ${STOCK_NAME}（${STOCK_CODE}）自動導航分析報告\n\n`;
  report += `> **查詢日期**：${today}  \n`;
  report += `> **資料來源**：優分析 UAnalyze 產業資料庫  \n`;
  report += `> **股票**：${STOCK_CODE} ${STOCK_NAME}\n\n---\n\n`;

  // ── 1. 股票分類評分（AI Reports）──
  if (aiData.data?.scores) {
    report += `# 股票分類評分\n\n`;
    aiData.data.scores.forEach(s => {
      report += `## ${s.name}：${s.score}/100\n\n`;
      (s.items || []).forEach(item => {
        report += `- **${item.reason}**`;
        if (item.process) report += `：${item.process}`;
        report += '\n';
      });
      report += '\n';
    });
    if (aiData.data.cycle) report += `> **循環週期**：${aiData.data.cycle}\n\n`;
    report += `---\n\n`;
  }

  // ── 2. 關鍵發展（Assist）──
  if (assist.data?.text) {
    report += `# 關鍵發展\n\n${assist.data.text}\n\n---\n\n`;
  }

  // ── 3. 自動導航各階段 ──
  stages.forEach(stage => {
    report += `# ${stage.name}\n\n`;
    (stage.steps || []).forEach(step => {
      report += `## STEP：${step.name}\n\n`;
      const refs = step.metadata?.ref || [];
      refs.forEach(ref => { if (ref.content) report += ref.content + '\n\n'; });
      if (step.metadata?.why) report += `> **為什麼看這個？** ${step.metadata.why}\n\n`;
      if (step.metadata?.guide) report += `> **指引：** ${step.metadata.guide}\n\n`;
      if (step.description) report += `> ${step.description}\n\n`;
      report += `---\n\n`;
    });
  });

  // ── 4. EPS 共識統計表格 ──
  const d = epsData.data?.data;
  if (d) {
    const rev = d['ua50189_cp']?.Data || {};
    const eps = d['ua50187_cp']?.Data || {};
    const coreEps = d['ua50209_cp']?.Data || {};
    if (Object.keys(rev).length > 0) {
      report += `\n# 法人預估 EPS & 營收共識統計\n\n`;
      report += `> 單位：營收（百萬元）、EPS（元）\n\n`;
      report += `| 年度 | 法人平均預估營收 | 法人平均預估EPS | 法人平均預估本業EPS |\n`;
      report += `|------|:---:|:---:|:---:|\n`;
      Object.keys(rev).forEach(year => {
        const label = year.includes('(f)') ? `**${year}**` : year;
        report += `| ${label} | ${rev[year] ?? '-'} | ${eps[year] ?? '-'} | ${coreEps[year] ?? '-'} |\n`;
      });
      report += `\n> **(f) = 法人預估值**\n\n---\n\n`;
    }
  }

  // ── 5. EPS 上下修趨勢（最近 12 筆）──
  const epsHistData = epsHist.data?.data;
  if (epsHistData) {
    report += `\n# 未來每年EPS預估上下修趨勢（最近資料）\n\n`;
    Object.entries(epsHistData).forEach(([key, series]) => {
      const name = series.ChineseAccount || key;
      const dataPoints = series.Data || {};
      const recent = Object.entries(dataPoints).slice(-8);
      if (recent.length === 0) return;
      report += `**${name}**\n\n`;
      report += `| 日期 | 預估值 |\n|------|------:|\n`;
      recent.forEach(([date, val]) => { report += `| ${date} | ${val} |\n`; });
      report += '\n';
    });
    report += `---\n\n`;
  }

  // ── 6. 月營收 YoY（最近 12 個月）──
  const monthlyData = monthly.data?.data;
  if (monthlyData) {
    const yoy = monthlyData['raw70008'];   // 月營收年增率
    const rev = Object.entries(monthlyData).find(([k, v]) => v.ChineseAccount?.includes('月營收') && !v.ChineseAccount?.includes('年增'))?.[1];
    if (yoy?.Data) {
      report += `\n# 月營收 VS 年增率（最近 12 個月）\n\n`;
      report += `| 月份 | 月營收年增率(%) | 月營收(千元) |\n|------|:---:|---:|\n`;
      const recent = Object.entries(yoy.Data).slice(-12);
      recent.forEach(([month, yoyVal]) => {
        const revVal = rev?.Data?.[month] ?? '-';
        report += `| ${month} | ${yoyVal} | ${revVal} |\n`;
      });
      report += `\n---\n\n`;
    }
  }

  // ── 7. 資本支出佔營收比重（最近 8 季）──
  const capexData = capex.data?.data;
  if (capexData) {
    const capexAmt = Object.values(capexData).find(v => v.ChineseAccount?.includes('資本支出金額'));
    const capexRatio = Object.values(capexData).find(v => v.ChineseAccount?.includes('佔營收'));
    if (capexAmt?.PeriodData) {
      report += `\n# 資本支出佔營收比重（最近 8 季）\n\n`;
      report += `| 季度 | 資本支出(千元) | 佔營收比重(%) |\n|------|---:|:---:|\n`;
      Object.entries(capexAmt.PeriodData).slice(-8).forEach(([q, amt]) => {
        const ratio = capexRatio?.PeriodData?.[q] ?? '-';
        report += `| ${q} | ${amt?.toLocaleString() ?? '-'} | ${ratio} |\n`;
      });
      report += `\n---\n\n`;
    }
  }

  // ── 存檔 ──
  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const filepath = `${REPORT_DIR}/${filename}`;
  fs.writeFileSync(filepath, report);
  console.log(`✅ 報告已存：${filepath} (${(report.length/1024).toFixed(1)} KB)`);

  // ── Push 到 GitHub ──
  console.log('🚀 Push 到 GitHub...');
  if (!fs.existsSync(REPO_LOCAL + '/.git')) {
    const ghToken = execSync('gh auth token', { encoding: 'utf8' }).trim();
    execSync(`git clone "https://${ghToken}@github.com/${REPORT_REPO}.git" ${REPO_LOCAL}`, { stdio: 'pipe' });
  }
  const ghToken = execSync('gh auth token', { encoding: 'utf8' }).trim();
  execSync(`cd ${REPO_LOCAL} && git config user.email "kiro5@uanalyze" && git config user.name "MuJianping"`, { stdio: 'pipe' });
  execSync(`cd ${REPO_LOCAL} && git remote set-url origin "https://${ghToken}@github.com/${REPORT_REPO}.git"`, { stdio: 'pipe' });
  execSync(`cd ${REPO_LOCAL} && git pull origin main --rebase 2>/dev/null || true`, { stdio: 'pipe' });

  const repoReportDir = `${REPO_LOCAL}/kiro/kiro5_劍屏/stock-analysis-reports/reports`;
  fs.mkdirSync(repoReportDir, { recursive: true });
  fs.copyFileSync(filepath, `${repoReportDir}/${filename}`);

  execSync(`cd ${REPO_LOCAL} && git add "kiro/kiro5_劍屏/stock-analysis-reports/reports/${filename}" && git commit -m "add: ${STOCK_NAME}(${STOCK_CODE}) 自動導航分析 ${dateStr}" && git push origin main`, { stdio: 'inherit' });

  console.log(`\n🎉 完成！`);
  console.log(`📎 https://github.com/${REPORT_REPO}/blob/main/kiro/kiro5_%E5%8A%8D%E5%B1%8F/stock-analysis-reports/reports/${encodeURIComponent(filename)}`);
}

run().catch(err => { console.error('❌ Error:', err.message); process.exit(1); });
