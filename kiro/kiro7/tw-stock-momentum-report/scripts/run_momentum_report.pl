#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;
use File::Path qw(make_path);
use POSIX qw(strftime);

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $notes_dir = "/home/agent/kiro-notes";
my $kiro7_dir = "$notes_dir/kiro7_韋小寶";
make_path($kiro7_dir) unless -d $kiro7_dir;

my $html_file = "$kiro7_dir/latest.html";
my $root_html_file = "$notes_dir/latest.html";

sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d{3})(?=\d)(?!\d*\.)/$1,/g;
    return reverse $text;
}

sub fetch_twse_t86_latest {
    my $now = time();
    for (my $i = 0; $i < 10; $i++) {
        my $t = $now - ($i * 86400);
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
        next if ($wday == 0 || $wday == 6);
        
        my $date_str = strftime("%Y%m%d", $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
        my $url = "https://www.twse.com.tw/rwd/zh/fund/T86?response=json&date=$date_str&selectType=ALLBUT0999";
        my $json = `curl -s -A "Mozilla/5.0" "$url"`;
        my $data = eval { decode_json($json) };
        if ($data && ref($data) eq 'HASH' && ($data->{stat} || '') eq 'OK' && $data->{data}) {
            my $display_date = sprintf("%s/%s/%s", substr($date_str,0,4), substr($date_str,4,2), substr($date_str,6,2));
            return ($display_date, $data->{data});
        }
        select(undef, undef, undef, 0.5);
    }
    die "Unable to fetch TWSE T86 data within last 10 days.\n";
}

sub fetch_twse_capital {
    my $json = `curl -s "https://openapi.twse.com.tw/v1/opendata/t187ap03_L"`;
    my $list = eval { decode_json($json) } || [];
    my %cap_map;
    for my $c (@$list) {
        my $code = $c->{"公司代號"};
        my $cap = $c->{"實收資本額"};
        next unless defined $code && defined $cap;
        $cap =~ s/,//g;
        $cap_map{$code} = {
            name => $c->{"公司簡稱"},
            capital => $cap + 0,
            shares => ($cap + 0) / 10,
        };
    }
    return \%cap_map;
}

my ($display_date, $t86_rows) = fetch_twse_t86_latest();
my $cap_map = fetch_twse_capital();

my @momentum_results;
for my $row (@$t86_rows) {
    my $code = $row->[0]; $code =~ s/\s+//g;
    my $name = $row->[1]; $name =~ s/\s+//g;
    
    my $foreign_buy = $row->[4]; $foreign_buy =~ s/,//g if defined $foreign_buy;
    my $sitc_buy = $row->[10]; $sitc_buy =~ s/,//g if defined $sitc_buy;
    my $total_buy = $row->[18]; $total_buy =~ s/,//g if defined $total_buy;
    
    next unless defined $foreign_buy && defined $sitc_buy && exists $cap_map->{$code};
    my $shares = $cap_map->{$code}->{shares};
    next if $shares <= 0;
    
    my $foreign_pct = ($foreign_buy / $shares) * 100;
    my $sitc_pct = ($sitc_buy / $shares) * 100;
    my $total_pct = ($total_buy / $shares) * 100;
    
    my $foreign_zhang = int($foreign_buy / 1000);
    my $sitc_zhang = int($sitc_buy / 1000);
    my $total_zhang = int($total_buy / 1000);
    
    my $momentum_score = ($sitc_pct * 3.0) + ($foreign_pct * 1.5);
    
    push @momentum_results, {
        code => $code,
        name => $name,
        foreign_zhang => $foreign_zhang,
        foreign_pct => $foreign_pct,
        sitc_zhang => $sitc_zhang,
        sitc_pct => $sitc_pct,
        total_zhang => $total_zhang,
        total_pct => $total_pct,
        momentum_score => $momentum_score
    };
}

@momentum_results = sort { $b->{momentum_score} <=> $a->{momentum_score} } @momentum_results;
my @top_sitc = sort { $b->{sitc_pct} <=> $a->{sitc_pct} } @momentum_results;

my $html = <<"HTML";
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>⚡ 台股動能量價與法人籌碼每日報告 (tw-stock-momentum-report)</title>
    <style>
        body {
            background-color: #050811;
            color: #f8fafc;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            margin: 0;
            padding: 20px;
        }
        .header {
            text-align: center;
            padding: 25px 0;
            border-bottom: 1px solid #1e293b;
            margin-bottom: 30px;
        }
        .header h1 {
            color: #facc15;
            margin: 0 0 10px 0;
            font-size: 28px;
        }
        .header p {
            color: #94a3b8;
            margin: 0;
            font-size: 14px;
        }
        .badge {
            display: inline-block;
            background-color: #0284c7;
            color: #ffffff;
            padding: 6px 14px;
            border-radius: 6px;
            font-size: 13px;
            font-weight: bold;
            margin-top: 12px;
        }
        .section-container {
            max-width: 1100px;
            margin: 0 auto 40px auto;
        }
        .section-title {
            font-size: 20px;
            font-weight: bold;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
            padding-bottom: 8px;
            border-bottom: 2px solid #1e293b;
        }
        .title-momentum { color: #facc15; border-color: #facc15; }
        .title-sitc { color: #ff334b; border-color: #ff334b; }
        table {
            width: 100%;
            border-collapse: collapse;
            background-color: #0f172a;
            border-radius: 8px;
            overflow: hidden;
            border: 1px solid #1e293b;
            margin-bottom: 25px;
        }
        th {
            background-color: #1e293b;
            color: #facc15;
            padding: 12px 15px;
            text-align: left;
            font-size: 14px;
        }
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #1e293b;
            font-size: 14px;
        }
        tr:hover {
            background-color: #1e293b;
        }
        .buy-val { color: #ff334b; font-weight: bold; }
        .foreign-val { color: #38bdf8; font-weight: bold; }
        .sitc-val { color: #facc15; font-weight: bold; }
        .score-val { color: #facc15; font-weight: bold; font-size: 15px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>⚡ 台股動能量價與法人籌碼每日報告 (tw-stock-momentum-report)</h1>
        <p>100% 台灣證券交易所 (TWSE) 官方 API | 高階動能評分選股系統</p>
        <div class="badge">最新交易日：$display_date 盤後即時</div>
    </div>
    
    <div class="section-container">
        <div class="section-title title-momentum">🚀 全市場法人籌碼動能強勢 TOP 15 ($display_date)</div>
        <table>
            <thead>
                <tr>
                    <th>名次</th>
                    <th>代號</th>
                    <th>股票名稱</th>
                    <th>投信買超 (張 / %)</th>
                    <th>外資買超 (張 / %)</th>
                    <th>動能綜合評分</th>
                </tr>
            </thead>
            <tbody>
HTML

for my $i (0..14) {
    last if $i >= @momentum_results;
    my $r = $momentum_results[$i];
    my $f_sign = $r->{foreign_zhang} >= 0 ? "+" : "";
    my $s_sign = $r->{sitc_zhang} >= 0 ? "+" : "";
    my $rank = $i + 1;
    $html .= sprintf(
        "<tr><td>%d</td><td><b>%s</b></td><td><b>%s</b></td><td class=\"sitc-val\">%s%s張 (%s%.2f%%)</td><td class=\"foreign-val\">%s%s張 (%s%.2f%%)</td><td class=\"score-val\">🔥 %.2f</td></tr>\n",
        $rank, $r->{code}, $r->{name}, $s_sign, commify($r->{sitc_zhang}), $s_sign, $r->{sitc_pct}, $f_sign, commify($r->{foreign_zhang}), $f_sign, $r->{foreign_pct}, $r->{momentum_score}
    );
}

$html .= <<"HTML";
            </tbody>
        </table>
    </div>

    <div class="section-container">
        <div class="section-title title-sitc">🔥 投信買超投本比 TOP 15 ($display_date)</div>
        <table>
            <thead>
                <tr>
                    <th>名次</th>
                    <th>代號</th>
                    <th>股票名稱</th>
                    <th>投信買超 (張)</th>
                    <th>投本比 (%)</th>
                </tr>
            </thead>
            <tbody>
HTML

for my $i (0..14) {
    last if $i >= @top_sitc;
    my $r = $top_sitc[$i];
    my $rank = $i + 1;
    $html .= sprintf(
        "<tr><td>%d</td><td><b>%s</b></td><td><b>%s</b></td><td class=\"buy-val\">+%s張</td><td class=\"buy-val\">+%.3f%%</td></tr>\n",
        $rank, $r->{code}, $r->{name}, commify($r->{sitc_zhang}), $r->{sitc_pct}
    );
}

$html .= <<"HTML";
            </tbody>
        </table>
    </div>
</body>
</html>
HTML

for my $file ($html_file, $root_html_file) {
    open my $fh_out, ">:encoding(UTF-8)", $file or die $!;
    print $fh_out $html;
    close $fh_out;
}

print "Generated HTML report successfully for $display_date!\n";
