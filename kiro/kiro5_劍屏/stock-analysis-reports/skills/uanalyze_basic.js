#!/usr/bin/env node
/**
 * Skill: 優分析自動導航完整查詢（含每個 STEP 對應圖表數據）
 * 使用方式: node pre_uanalyze_query.js <股票代號> [股票名稱]
 * 例: node pre_uanalyze_query.js 3661 世芯-KY
 *
 * version: 2.0.0
 * updated: 2026-04-28
 * changelog:
 *   v2.0.0 - 每個 STEP 自動帶入對應圖表數字（累計月營收/EPS追蹤/季預估/資本支出等）
 *   v1.1.0 - 新增圖表數據區塊
 *   v1.0.0 - 基本 guides + EPS API
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

// 取最近 N 筆資料
function recentEntries(obj, n = 6) {
  return Object.entries(obj || {}).slice(-n);
}

// 格式化數字
function fmt(v) {
  if (v == null) return '-';
  if (typeof v === 'number') return v.toLocaleString();
  return v;
}

// 根據 laboratory_id 判斷圖表類型，產生對應的文字描述
function buildChartSection(labId, singleKey, chartData) {
  const id = String(labId);
  const d = chartData;

  // 累計月營收 vs 法人共識（41616）
  if (id === '41616') {
    const cumRev = d.cumRev?.data?.data;
    if (!cumRev) return '';
    const actual = cumRev['ua70248_cp']?.Data || {};
    const consensus = cumRev['ua70274_cp']?.Data || {};
    const myEst = cumRev['ua70249_cp']?.Data || {};
    const recentActual = recentEntries(actual, 4);
    const latestMonth = recentActual[recentActual.length - 1];
    const latestConsensus = recentEntries(consensus, 1)[0];
    const diffPct = latestMonth && latestConsensus
      ? (((latestMonth[1] - latestConsensus[1]) / latestConsensus[1]) * 100).toFixed(1)
      : null;

    let s = `> **📊 累計月營收 vs 法人共識**\n>\n`;
    s += `> | 月份 | 累計實際營收(千元) | 法人共識(千元) |\n`;
    s += `> |------|---:|---:|\n`;
    recentActual.forEach(([m, v]) => {
      const c = consensus[m];
      s += `> | ${m}月 | ${fmt(v)} | ${c ? fmt(c) : '-'} |\n`;
    });
    if (diffPct !== null) {
      const arrow = parseFloat(diffPct) >= 0 ? '↑' : '↓';
      s += `>\n> **趨勢**：最新累計營收 vs 法人共識 ${arrow} ${Math.abs(diffPct)}%\n`;
    }
    return s + '\n';
  }

  // 季EPS/營收追蹤（32845）
  if (id === '32845') {
    const epsTrack = d.epsTrack?.data?.data;
    const revTrack = d.revTrack?.data?.data;
    if (!epsTrack && !revTrack) return '';

    let s = `> **📊 季EPS & 營收實際 vs 法人共識**\n>\n`;

    if (epsTrack) {
      const actual = epsTrack['ua60286_cp']?.Data || {};
      const forecast = epsTrack['ua60285_cp']?.Data || {};
      s += `> **EPS 追蹤（最近 4 季）**\n>\n`;
      s += `> | 季度 | 實際EPS | 法人共識 |\n> |------|:---:|:---:|\n`;
      recentEntries(actual, 4).forEach(([q, v]) => {
        s += `> | ${q} | ${fmt(v)} | ${fmt(forecast[q])} |\n`;
      });
      // 未來預估
      const futureF = recentEntries(forecast, 4).filter(([q]) => !actual[q]);
      if (futureF.length > 0) {
        s += `>\n> **未來法人預估**\n>\n`;
        s += `> | 季度 | 法人共識EPS |\n> |------|:---:|\n`;
        futureF.forEach(([q, v]) => { s += `> | ${q} | ${fmt(v)} |\n`; });
      }
    }

    if (revTrack) {
      const actual = revTrack['ua60286_cp']?.Data || {};
      const forecast = revTrack['ua60285_cp']?.Data || {};
      s += `>\n> **營收追蹤（最近 4 季，百萬元）**\n>\n`;
      s += `> | 季度 | 實際營收 | 法人共識 |\n> |------|---:|---:|\n`;
      recentEntries(actual, 4).forEach(([q, v]) => {
        s += `> | ${q} | ${fmt(v)} | ${fmt(forecast[q])} |\n`;
      });
    }
    return s + '\n';
  }

  // 費用率/ROIC（41615）
  if (id === '41615') {
    const capex = d.capex?.data?.data;
    if (!capex) return '';
    const capexAmt = Object.values(capex).find(v => v.ChineseAccount?.includes('資本支出金額'));
    const capexRatio = Object.values(capex).find(v => v.ChineseAccount?.includes('佔營收'));
    if (!capexAmt?.PeriodData) return '';

    let s = `> **📊 資本支出佔營收比重（最近 6 季）**\n>\n`;
    s += `> | 季度 | 資本支出(千元) | 佔營收(%) |\n> |------|---:|:---:|\n`;
    recentEntries(capexAmt.PeriodData, 6).forEach(([q, v]) => {
      s += `> | ${q} | ${fmt(v)} | ${fmt(capexRatio?.PeriodData?.[q])} |\n`;
    });
    return s + '\n';
  }

  // 存貨相關（41642）
  if (id === '41642') {
    const inv = d.inv?.data?.data;
    const invDetail = d.invDetail?.data?.data;
    const contract = d.contract?.data?.data;
    const turnover = d.turnover?.data?.data;
    let s = '';

    // 存銷比
    if (inv) {
      const invAmt = Object.values(inv).find(v => v.ChineseAccount?.includes('存貨'));
      const revAmt = Object.values(inv).find(v => v.ChineseAccount?.includes('月營收'));
      const ratio = Object.values(inv).find(v => v.ChineseAccount?.includes('存銷比'));
      if (ratio?.Data) {
        s += `> **📊 存貨銷售比（最近 6 個月）**\n>\n`;
        s += `> | 月份 | 存貨(千元) | 月營收(千元) | 存銷比 |\n> |------|---:|---:|:---:|\n`;
        recentEntries(ratio.Data, 6).forEach(([m, r]) => {
          s += `> | ${m} | ${fmt(invAmt?.Data?.[m])} | ${fmt(revAmt?.Data?.[m])} | ${r} |\n`;
        });
        const lastRatio = recentEntries(ratio.Data, 1)[0]?.[1];
        if (lastRatio) s += `>\n> **趨勢**：最新存銷比 ${lastRatio}（>1 代表存貨偏高）\n`;
        s += '\n';
      }
    }

    // 存貨細項
    if (invDetail) {
      const raw = Object.values(invDetail).find(v => v.ChineseAccount === '原料');
      const wip = Object.values(invDetail).find(v => v.ChineseAccount === '在製品');
      const fg = Object.values(invDetail).find(v => v.ChineseAccount === '製成品');
      if (wip?.PeriodData) {
        s += `> **📊 存貨細項（最近 4 季，千元）**\n>\n`;
        s += `> | 季度 | 原料 | 在製品 | 製成品 |\n> |------|---:|---:|---:|\n`;
        recentEntries(wip.PeriodData, 4).forEach(([q, w]) => {
          s += `> | ${q} | ${fmt(raw?.PeriodData?.[q])} | ${fmt(w)} | ${fmt(fg?.PeriodData?.[q])} |\n`;
        });
        s += '\n';
      }
    }

    // 合約負債
    if (contract) {
      const cl = Object.values(contract).find(v => v.ChineseAccount?.includes('合約負債') && !v.ChineseAccount?.includes('比重'));
      const clRatio = Object.values(contract).find(v => v.ChineseAccount?.includes('比重'));
      if (cl?.PeriodData) {
        s += `> **📊 合約負債佔季營收比重（最近 4 季）**\n>\n`;
        s += `> | 季度 | 合約負債(千元) | 佔季營收(%) |\n> |------|---:|:---:|\n`;
        recentEntries(cl.PeriodData, 4).forEach(([q, v]) => {
          s += `> | ${q} | ${fmt(v)} | ${fmt(clRatio?.PeriodData?.[q])} |\n`;
        });
        s += '\n';
      }
    }

    // 存貨週轉率
    if (turnover) {
      const tr = Object.values(turnover).find(v => v.ChineseAccount?.includes('週轉率'));
      const gm = Object.values(turnover).find(v => v.ChineseAccount?.includes('毛利率'));
      if (tr?.PeriodData) {
        s += `> **📊 存貨週轉率 & 毛利率（最近 4 季）**\n>\n`;
        s += `> | 季度 | 存貨週轉率 | 毛利率(%) |\n> |------|:---:|:---:|\n`;
        recentEntries(tr.PeriodData, 4).forEach(([q, v]) => {
          s += `> | ${q} | ${v} | ${fmt(gm?.PeriodData?.[q])} |\n`;
        });
        s += '\n';
      }
    }

    return s || '';
  }

  return '';
}

async function run() {
  // ── 直接用 curl 取得 access_token（api.uanalyze.com.tw 需透過 Cloudflare IP）──
  console.log('🔐 登入中...');
  const loginResult = JSON.parse(execSync(
    `curl -s --max-time 15 --resolve 'api.uanalyze.com.tw:443:172.67.143.166' ` +
    `-X POST https://api.uanalyze.com.tw/auth/token ` +
    `-H 'Content-Type: application/json' ` +
    `-H 'Origin: https://pro.uanalyze.com.tw' ` +
    `-d '{"email":"${process.env.UANALYZE_USERNAME}","password":"${process.env.UANALYZE_PASSWORD}"}'`
  ).toString());
  if (loginResult.status !== 'success') throw new Error('登入失敗: ' + JSON.stringify(loginResult));
  const accessToken = loginResult.data.access_token;
  const tokenType = loginResult.data.token_type || 'Bearer';
  console.log('✅ 登入成功');
  console.log('✅ 取得 access_token');

  // ── 用 Node.js fetch / curl 呼叫 API ──
  console.log(`📋 查詢 ${STOCK_CODE} 資料...`);
  // data.uanalyze.twobitto.com 可直接 fetch；cronjob.uanalyze.com.tw 需透過 Cloudflare IP
  const nodeGet = async (url) => {
    const resp = await fetch(url, { headers: { 'Authorization': `${tokenType} ${accessToken}` } });
    return await resp.text();
  };
  const curlGet = (url) => execSync(
    `curl -s --max-time 15 --resolve 'cronjob.uanalyze.com.tw:443:172.67.143.166' '${url}' -H 'Authorization: ${tokenType} ${accessToken}' -H 'Origin: https://pro.uanalyze.com.tw'`
  ).toString();
  const base = 'https://cronjob.uanalyze.com.tw/data_fetch/api';
  const apiData = {
    guides:    await nodeGet(`https://data.uanalyze.twobitto.com/api/guides/${STOCK_CODE}`),
    eps:       curlGet(`${base}/EPSRevenueConsensusEstimate/${STOCK_CODE}`),
    ai:        await nodeGet(`https://data.uanalyze.twobitto.com/api/ai/reports?stock=${STOCK_CODE}&ai_model=gpt-4.1-mini`),
    assist:    await nodeGet(`https://data.uanalyze.twobitto.com/api/assist/reports?stock=${STOCK_CODE}`),
    monthly:   curlGet(`${base}/MonthlyRevenueAndYoY/${STOCK_CODE}`),
    cumRev:    curlGet(`${base}/MonthlyRevenueTrackingConcensuslModule/${STOCK_CODE}`),
    epsTrack:  curlGet(`${base}/EPSTrackingActualVSForecastModule/${STOCK_CODE}`),
    revTrack:  curlGet(`${base}/RevenueTrackingActualVSForecastModule/${STOCK_CODE}`),
    capex:     curlGet(`${base}/CapexToSalesRatio/${STOCK_CODE}`),
    epsHist:   curlGet(`${base}/HustoricalForecastEPS_Value_Yearly/${STOCK_CODE}`),
    inv:       curlGet(`${base}/InventoryToRecentSales/${STOCK_CODE}`),
    invDetail: curlGet(`${base}/InventoriesDatailOriginal/${STOCK_CODE}`),
    contract:  curlGet(`${base}/CurrentContractLiabilitiesVSRevenue/${STOCK_CODE}`),
    turnover:  curlGet(`${base}/InventoriesTurnoverTimes_Revenue_GrossMargin/${STOCK_CODE}`),
  };

  // ── 解析 ──
  const parse = (raw) => { try { return JSON.parse(raw); } catch(e) { return {}; } };
  const guidesData = parse(apiData.guides);
  const stages = guidesData.data?.stages || [];
  const aiData    = parse(apiData.ai);
  const epsData   = parse(apiData.eps);
  const assist    = parse(apiData.assist);
  const epsHist   = parse(apiData.epsHist);

  // 圖表數據集合（傳給 buildChartSection）
  const chartData = {
    cumRev:   parse(apiData.cumRev),
    epsTrack: parse(apiData.epsTrack),
    revTrack: parse(apiData.revTrack),
    monthly:  parse(apiData.monthly),
    capex:    parse(apiData.capex),
    inv:      parse(apiData.inv),
    invDetail: parse(apiData.invDetail),
    contract: parse(apiData.contract),
    turnover: parse(apiData.turnover),
  };

  console.log(`✅ 自動導航：${stages.length} 個階段，共 ${stages.reduce((n, s) => n + s.steps.length, 0)} 個 STEP`);

  // ── 建立報告 ──
  console.log('📝 建立報告...');
  const today = new Date().toISOString().slice(0, 10);
  const dateStr = today.replace(/-/g, '');
  const filename = `${STOCK_NAME}(${STOCK_CODE})_pre_${dateStr}.md`;

  let report = `# ${STOCK_NAME}（${STOCK_CODE}）自動導航分析報告\n\n`;
  report += `> **查詢日期**：${today}  \n`;
  report += `> **資料來源**：優分析 UAnalyze 產業資料庫  \n`;
  report += `> **股票**：${STOCK_CODE} ${STOCK_NAME}\n\n---\n\n`;

  // 1. 股票分類評分
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

  // 2. 關鍵發展
  if (assist.data?.text) {
    report += `# 關鍵發展\n\n${assist.data.text}\n\n---\n\n`;
  }

  // 3. 自動導航各階段（每個 STEP 帶圖表數據）
  let stepNum = 0;
  stages.forEach((stage, si) => {
    report += `# ${stage.name}\n\n`;
    (stage.steps || []).forEach((step, i) => {
      stepNum++;
      const m = step.metadata;
      report += `## 第 ${stepNum} 步：${step.name}\n\n`;

      // 文字內容
      const refs = m?.ref || [];
      refs.forEach(ref => { if (ref.content) report += ref.content + '\n\n'; });
      if (m?.why) report += `> **為什麼看這個？** ${m.why}\n\n`;
      if (m?.guide) report += `> **指引：** ${m.guide}\n\n`;
      if (step.description) report += `> ${step.description}\n\n`;

      // 圖表數據（依 laboratory_id 自動帶入）
      if (m?.single_type === 'chart' && m?.laboratory_id) {
        const chartSection = buildChartSection(m.laboratory_id, m.single_key, chartData);
        if (chartSection) report += chartSection;
      }

      report += `---\n\n`;
    });
  });

  // 4. EPS 共識統計
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

  // 5. EPS 上下修趨勢
  const epsHistData = epsHist.data?.data;
  if (epsHistData) {
    report += `\n# 未來每年EPS預估上下修趨勢（最近資料）\n\n`;
    Object.entries(epsHistData).forEach(([key, series]) => {
      const name = series.ChineseAccount || key;
      const recent = recentEntries(series.Data || {}, 6);
      if (recent.length === 0) return;
      report += `**${name}**\n\n| 日期 | 預估值 |\n|------|------:|\n`;
      recent.forEach(([date, val]) => { report += `| ${date} | ${val} |\n`; });
      report += '\n';
    });
    report += `---\n\n`;
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
