#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d{3})(?=\d)(?!\d*\.)/$1,/g;
    return reverse $text;
}

# 1. Fetch TWSE Company Capital
my $json_cap = `curl -s "https://openapi.twse.com.tw/v1/opendata/t187ap03_L"`;
my $cap_list = decode_json($json_cap);
my %capital;
for my $c (@$cap_list) {
    my $code = $c->{"公司代號"};
    my $cap = $c->{"實收資本額"};
    $cap =~ s/,//g;
    $capital{$code} = {
        name => $c->{"公司簡稱"},
        capital => $cap + 0,
        shares => ($cap + 0) / 10,
        shares_zhang => ($cap + 0) / 10000,
    };
}

# 2. Fetch TWSE T86 (Latest trading day)
my $json_t86 = `curl -s "https://www.twse.com.tw/rwd/zh/fund/T86?response=json&selectType=ALLBUT0999"`;
my $t86_data = decode_json($json_t86);
my $raw_date = $t86_data->{date} || "20260814";
my $formatted_date = length($raw_date) == 8 ? substr($raw_date, 0, 4) . "-" . substr($raw_date, 4, 2) . "-" . substr($raw_date, 6, 2) : $raw_date;

my @results;
for my $row (@{$t86_data->{data}}) {
    my $code = $row->[0]; $code =~ s/\s+//g;
    next unless exists $capital{$code};
    
    my $name = $row->[1]; $name =~ s/\s+//g;
    my $sitc_buy = $row->[10]; $sitc_buy =~ s/,//g; # 投信買賣超股數
    my $foreign_buy = $row->[4]; $foreign_buy =~ s/,//g; # 外陸資買賣超股數
    my $total_buy = $row->[18]; $total_buy =~ s/,//g; # 三大法人買賣超
    
    my $shares = $capital{$code}->{shares};
    next if $shares <= 0;
    
    my $sitc_ratio = ($sitc_buy / $shares) * 100;
    
    push @results, {
        code => $code,
        name => $name,
        shares_zhang => int($shares / 1000),
        sitc_buy_zhang => int($sitc_buy / 1000),
        sitc_ratio => $sitc_ratio,
        foreign_buy_zhang => int($foreign_buy / 1000),
        total_buy_zhang => int($total_buy / 1000),
    };
}

my @buy_top = sort { $b->{sitc_ratio} <=> $a->{sitc_ratio} } @results;
my @sell_top = sort { $a->{sitc_ratio} <=> $b->{sitc_ratio} } @results;

# 3. Fetch TPEx Data
my $json_tpex_buy = `curl -s -H "User-Agent: Mozilla/5.0" "https://www.tpex.org.tw/www/zh-tw/insti/sitcStat?type=Daily&searchType=buy&response=json"`;
my $tpex_buy = decode_json($json_tpex_buy);
my $tpex_buy_list = $tpex_buy->{tables}[0]{data} || [];

my $json_tpex_sell = `curl -s -H "User-Agent: Mozilla/5.0" "https://www.tpex.org.tw/www/zh-tw/insti/sitcStat?type=Daily&searchType=sell&response=json"`;
my $tpex_sell = decode_json($json_tpex_sell);
my $tpex_sell_list = $tpex_sell->{tables}[0]{data} || [];

# Generate HTML
my $html_file = shift || "/tmp/latest.html";

open(my $fh, '>:encoding(UTF-8)', $html_file) or die "Could not open file '$html_file' $!";

print $fh <<"HTML";
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>即時投信買賣超與投本比分析報告 ($formatted_date) | kiro7 韋小寶</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&family=Noto+Sans+TC:wght@400;500;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #0b0f19;
            --card-bg: #151d30;
            --card-border: #232f48;
            --text-main: #f1f5f9;
            --text-sub: #94a3b8;
            --accent-gold: #f59e0b;
            --accent-blue: #3b82f6;
            --green-buy: #10b981;
            --red-sell: #ef4444;
            --badge-bg: #1e293b;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            font-family: 'Inter', 'Noto Sans TC', sans-serif;
        }

        body {
            background-color: var(--bg-color);
            color: var(--text-main);
            padding: 24px 16px;
            line-height: 1.5;
        }

        .container {
            max-width: 1280px;
            margin: 0 auto;
        }

        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            padding-bottom: 20px;
            margin-bottom: 24px;
            border-bottom: 1px solid var(--card-border);
        }

        .title-group h1 {
            font-size: 1.8rem;
            font-weight: 700;
            background: linear-gradient(135deg, #f59e0b, #3b82f6);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 6px;
        }

        .title-group p {
            color: var(--text-sub);
            font-size: 0.95rem;
        }

        .meta-badge {
            background: rgba(59, 130, 246, 0.15);
            border: 1px solid rgba(59, 130, 246, 0.3);
            color: var(--accent-blue);
            padding: 6px 14px;
            border-radius: 20px;
            font-size: 0.85rem;
            font-weight: 600;
        }

        /* Stat Cards */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }

        .stat-card {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 12px;
            padding: 18px 20px;
            transition: transform 0.2s, border-color 0.2s;
        }

        .stat-card:hover {
            transform: translateY(-2px);
            border-color: var(--accent-blue);
        }

        .stat-card .label {
            font-size: 0.85rem;
            color: var(--text-sub);
            margin-bottom: 8px;
        }

        .stat-card .value {
            font-size: 1.5rem;
            font-weight: 700;
        }

        .stat-card .value.buy { color: var(--green-buy); }
        .stat-card .value.sell { color: var(--red-sell); }
        .stat-card .value.gold { color: var(--accent-gold); }

        /* Control Bar */
        .controls {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 16px;
            margin-bottom: 20px;
        }

        .tabs {
            display: flex;
            gap: 8px;
            background: var(--card-bg);
            padding: 4px;
            border-radius: 10px;
            border: 1px solid var(--card-border);
        }

        .tab-btn {
            background: transparent;
            border: none;
            color: var(--text-sub);
            padding: 8px 16px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.9rem;
            cursor: pointer;
            transition: all 0.2s;
        }

        .tab-btn.active {
            background: var(--accent-blue);
            color: #ffffff;
        }

        .search-input {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            color: var(--text-main);
            padding: 10px 16px;
            border-radius: 10px;
            font-size: 0.9rem;
            outline: none;
            width: 260px;
            transition: border-color 0.2s;
        }

        .search-input:focus {
            border-color: var(--accent-gold);
        }

        /* Table */
        .table-container {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 12px;
            overflow-x: auto;
            margin-bottom: 30px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
            font-size: 0.92rem;
        }

        th {
            background: #1e293b;
            color: var(--text-sub);
            padding: 14px 16px;
            font-weight: 600;
            border-bottom: 1px solid var(--card-border);
            white-space: nowrap;
        }

        td {
            padding: 14px 16px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.04);
            white-space: nowrap;
        }

        tr:hover td {
            background: rgba(255, 255, 255, 0.03);
        }

        .code-cell {
            font-family: monospace;
            font-weight: 700;
            color: var(--accent-gold);
        }

        .name-cell {
            font-weight: 600;
        }

        .buy-text { color: var(--green-buy); font-weight: 600; }
        .sell-text { color: var(--red-sell); font-weight: 600; }

        footer {
            text-align: center;
            color: var(--text-sub);
            font-size: 0.85rem;
            padding: 20px 0;
            border-top: 1px solid var(--card-border);
            margin-top: 40px;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="title-group">
                <h1>即時投信買賣超與投本比分析報告</h1>
                <p>資料日期：$formatted_date &nbsp;|&nbsp; 報告生成器：kiro7 韋小寶 Multi-Agent Team</p>
            </div>
            <div class="meta-badge">官方原生地 API 即時連線</div>
        </header>

        <div class="stats-grid">
            <div class="stat-card">
                <div class="label">上市投本比冠軍</div>
                <div class="value gold">$buy_top[0]{name} ($buy_top[0]{code})</div>
                <div class="label" style="margin-top:4px;">投本比 +@{[sprintf("%.3f", $buy_top[0]{sitc_ratio})]}% / 買超 $buy_top[0]{sitc_buy_zhang} 張</div>
            </div>
            <div class="stat-card">
                <div class="label">上市投賣比警訊</div>
                <div class="value sell">$sell_top[0]{name} ($sell_top[0]{code})</div>
                <div class="label" style="margin-top:4px;">投賣比 @{[sprintf("%.3f", $sell_top[0]{sitc_ratio})]}% / 賣超 $sell_top[0]{sitc_buy_zhang} 張</div>
            </div>
            <div class="stat-card">
                <div class="label">上櫃買超冠軍</div>
                <div class="value buy">@{[ $tpex_buy_list->[0][2] || '無' ]} (@{[ $tpex_buy_list->[0][1] || '' ]})</div>
                <div class="label" style="margin-top:4px;">買超 @{[ $tpex_buy_list->[0][5] || '0' ]} 張</div>
            </div>
            <div class="stat-card">
                <div class="label">上櫃賣超第一</div>
                <div class="value sell">@{[ $tpex_sell_list->[0][2] || '無' ]} (@{[ $tpex_sell_list->[0][1] || '' ]})</div>
                <div class="label" style="margin-top:4px;">賣超 @{[ $tpex_sell_list->[0][5] || '0' ]} 張</div>
            </div>
        </div>

        <div class="controls">
            <div class="tabs">
                <button class="tab-btn active" onclick="showTab('twse-buy')">📈 上市買超投本比 TOP 20</button>
                <button class="tab-btn" onclick="showTab('twse-sell')">📉 上市賣超投本比 TOP 20</button>
                <button class="tab-btn" onclick="showTab('tpex')">🟢 上櫃投信買賣超焦點榜</button>
            </div>
            <input type="text" class="search-input" id="searchInput" placeholder="🔍 搜尋股號或股名..." onkeyup="filterTable()">
        </div>

        <!-- Section 1: TWSE Buy -->
        <div id="sec-twse-buy" class="table-section">
            <div class="table-container">
                <table id="table-twse-buy">
                    <thead>
                        <tr>
                            <th>名次</th>
                            <th>股號</th>
                            <th>股票名稱</th>
                            <th>股本發行張數</th>
                            <th>投信買超(張)</th>
                            <th>投本比 (%)</th>
                        </tr>
                    </thead>
                    <tbody>
HTML

for my $i (0..19) {
    last if $i >= @buy_top;
    my $r = $buy_top[$i];
    my $rank = $i + 1;
    my $ratio_fmt = sprintf("%.3f", $r->{sitc_ratio});
    my $sh_fmt = commify($r->{shares_zhang});
    my $buy_fmt = commify($r->{sitc_buy_zhang});
    print $fh <<"TR";
                        <tr>
                            <td><strong>$rank</strong></td>
                            <td class="code-cell">$r->{code}</td>
                            <td class="name-cell">$r->{name}</td>
                            <td>$sh_fmt</td>
                            <td class="buy-text">+$buy_fmt</td>
                            <td class="buy-text">+$ratio_fmt%</td>
                        </tr>
TR
}

print $fh <<"HTML";
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Section 2: TWSE Sell -->
        <div id="sec-twse-sell" class="table-section" style="display:none;">
            <div class="table-container">
                <table id="table-twse-sell">
                    <thead>
                        <tr>
                            <th>名次</th>
                            <th>股號</th>
                            <th>股票名稱</th>
                            <th>股本發行張數</th>
                            <th>投信賣超(張)</th>
                            <th>投賣比 (%)</th>
                        </tr>
                    </thead>
                    <tbody>
HTML

for my $i (0..19) {
    last if $i >= @sell_top;
    my $r = $sell_top[$i];
    my $rank = $i + 1;
    my $ratio_fmt = sprintf("%.3f", $r->{sitc_ratio});
    my $sh_fmt = commify($r->{shares_zhang});
    my $sell_fmt = commify($r->{sitc_buy_zhang});
    print $fh <<"TR";
                        <tr>
                            <td><strong>$rank</strong></td>
                            <td class="code-cell">$r->{code}</td>
                            <td class="name-cell">$r->{name}</td>
                            <td>$sh_fmt</td>
                            <td class="sell-text">$sell_fmt</td>
                            <td class="sell-text">$ratio_fmt%</td>
                        </tr>
TR
}

print $fh <<"HTML";
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Section 3: TPEx -->
        <div id="sec-tpex" class="table-section" style="display:none;">
            <h3 style="margin-bottom:12px; font-size:1.1rem; color:var(--green-buy);">🟢 上櫃 投信買超 TOP</h3>
            <div class="table-container" style="margin-bottom:24px;">
                <table id="table-tpex-buy">
                    <thead>
                        <tr>
                            <th>排行</th>
                            <th>股號</th>
                            <th>股票名稱</th>
                            <th>買進(張)</th>
                            <th>賣出(張)</th>
                            <th>買賣超(張)</th>
                        </tr>
                    </thead>
                    <tbody>
HTML

for my $row (@$tpex_buy_list) {
    print $fh <<"TR";
                        <tr>
                            <td><strong>$row->[0]</strong></td>
                            <td class="code-cell">$row->[1]</td>
                            <td class="name-cell">$row->[2]</td>
                            <td>$row->[3]</td>
                            <td>$row->[4]</td>
                            <td class="buy-text">+$row->[5]</td>
                        </tr>
TR
}

print $fh <<"HTML";
                    </tbody>
                </table>
            </div>

            <h3 style="margin-bottom:12px; font-size:1.1rem; color:var(--red-sell);">🔴 上櫃 投信賣超 TOP</h3>
            <div class="table-container">
                <table id="table-tpex-sell">
                    <thead>
                        <tr>
                            <th>排行</th>
                            <th>股號</th>
                            <th>股票名稱</th>
                            <th>買進(張)</th>
                            <th>賣出(張)</th>
                            <th>買賣超(張)</th>
                        </tr>
                    </thead>
                    <tbody>
HTML

for my $row (@$tpex_sell_list) {
    print $fh <<"TR";
                        <tr>
                            <td><strong>$row->[0]</strong></td>
                            <td class="code-cell">$row->[1]</td>
                            <td class="name-cell">$row->[2]</td>
                            <td>$row->[3]</td>
                            <td>$row->[4]</td>
                            <td class="sell-text">$row->[5]</td>
                        </tr>
TR
}

print $fh <<"HTML";
                    </tbody>
                </table>
            </div>
        </div>

        <footer>
            證券數據來源：臺灣證券交易所 (TWSE) & 證券櫃檯買賣中心 (TPEx) 官方開放資料<br>
            由 韋小寶 kiro7 隨機應變即時生成 | MasonLee 大老闆專屬分析系統
        </footer>
    </div>

    <script>
        function showTab(tabId) {
            document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
            document.querySelectorAll('.table-section').forEach(sec => sec.style.display = 'none');
            
            if (tabId === 'twse-buy') {
                document.getElementById('sec-twse-buy').style.display = 'block';
                event.target.classList.add('active');
            } else if (tabId === 'twse-sell') {
                document.getElementById('sec-twse-sell').style.display = 'block';
                event.target.classList.add('active');
            } else if (tabId === 'tpex') {
                document.getElementById('sec-tpex').style.display = 'block';
                event.target.classList.add('active');
            }
            filterTable();
        }

        function filterTable() {
            const input = document.getElementById('searchInput').value.toUpperCase();
            const activeSection = document.querySelector('.table-section:not([style*="display: none"])');
            if (!activeSection) return;

            const tables = activeSection.querySelectorAll('table');
            tables.forEach(table => {
                const tr = table.getElementsByTagName('tr');
                for (let i = 1; i < tr.length; i++) {
                    const tdCode = tr[i].getElementsByTagName('td')[1];
                    const tdName = tr[i].getElementsByTagName('td')[2];
                    if (tdCode || tdName) {
                        const codeVal = tdCode.textContent || tdCode.innerText;
                        const nameVal = tdName.textContent || tdName.innerText;
                        if (codeVal.toUpperCase().indexOf(input) > -1 || nameVal.toUpperCase().indexOf(input) > -1) {
                            tr[i].style.display = '';
                        } else {
                            tr[i].style.display = 'none';
                        }
                    }
                }
            });
        }
    </script>
</body>
</html>
HTML

close($fh);
print "HTML report generated: $html_file\n";
