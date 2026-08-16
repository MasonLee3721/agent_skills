#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;

use POSIX qw(strftime);

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

sub fetch_json_curl {
    my ($url) = @_;
    my $json_text = `curl -s "$url"`;
    return eval { decode_json($json_text) } || undef;
}

# 動態向後搜尋最新成功發布之交易日 (最多倒退 10 天處理假日、休市與盤中未發布)
sub find_latest_trading_date {
    my ($specified) = @_;
    if (defined $specified && $specified =~ /^\d{8}$/) {
        my $url = "https://www.twse.com.tw/rwd/zh/fund/T86?response=json&date=$specified&selectType=ALLBUT0999";
        my $data = fetch_json_curl($url);
        return ($specified, $data);
    }

    my $now = time();
    for (my $i = 0; $i < 10; $i++) {
        my $t = $now - ($i * 86400);
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
        next if ($wday == 0 || $wday == 6); # 跳過假日

        my $date_str = strftime("%Y%m%d", $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
        my $url = "https://www.twse.com.tw/rwd/zh/fund/T86?response=json&date=$date_str&selectType=ALLBUT0999";
        my $data = fetch_json_curl($url);

        if ($data && ref($data) eq 'HASH' && ($data->{stat} || '') eq 'OK' && $data->{data} && ref($data->{data}) eq 'ARRAY' && @{$data->{data}} > 0) {
            return ($date_str, $data);
        }
    }
    return (strftime("%Y%m%d", localtime()), undef);
}

my $specified_param = (@ARGV && $ARGV[0] =~ /^\d{8}$/) ? $ARGV[0] : undef;
my ($target_date, $t86_data) = find_latest_trading_date($specified_param);

# 若資料取得失敗，必須拋出錯誤並 exit non-zero，杜絕假成功
unless (defined $t86_data && ref($t86_data) eq 'HASH' && ($t86_data->{stat} || '') eq 'OK' && $t86_data->{data} && ref($t86_data->{data}) eq 'ARRAY' && @{$t86_data->{data}} > 0) {
    my $msg = defined $specified_param
        ? "❌ 指定交易日 ($specified_param) 無法取得 TWSE 數據 (無效日期、休市或 API 異常)"
        : "❌ 回溯搜尋近 10 日皆無法取得 TWSE 數據 (請檢查網路連線或 API 狀態)";
    die "$msg\n";
}

my $display_date = sprintf("%s/%s/%s", substr($target_date,0,4), substr($target_date,4,2), substr($target_date,6,2));

# 1. Fetch TWSE Capital
my $json_cap = `curl -s "https://openapi.twse.com.tw/v1/opendata/t187ap03_L"`;
my $cap_list = eval { decode_json($json_cap) } || [];
my %capital;
for my $c (@$cap_list) {
    my $code = $c->{"公司代號"};
    my $cap = $c->{"實收資本額"};
    next unless defined $code && defined $cap;
    $cap =~ s/,//g;
    $capital{$code} = {
        name => $c->{"公司簡稱"},
        capital => $cap + 0,
        shares => ($cap + 0) / 10,
    };
}

my @top_stocks;
if ($t86_data && ref($t86_data) eq 'HASH' && $t86_data->{data} && ref($t86_data->{data}) eq 'ARRAY') {
    for my $row (@{$t86_data->{data}}) {
        my $code = $row->[0]; $code =~ s/\s+//g if defined $code;
        next unless defined $code && exists $capital{$code};
        
        my $name = $row->[1]; $name =~ s/\s+//g if defined $name;
        my $sitc_buy = $row->[10]; $sitc_buy =~ s/,//g if defined $sitc_buy; # 投信買賣超股數
        my $shares = $capital{$code}->{shares};
        next if !defined $sitc_buy || $shares <= 0 || $sitc_buy <= 0;
        
        my $sitc_ratio = ($sitc_buy / $shares) * 100;
        
        push @top_stocks, {
            code => $code,
            name => $name,
            shares_zhang => int($shares / 1000),
            sitc_buy_zhang => int($sitc_buy / 1000),
            sitc_ratio => $sitc_ratio,
        };
    }
}

@top_stocks = sort { $b->{sitc_ratio} <=> $a->{sitc_ratio} } @top_stocks;

# Fetch daily quotes
my $json_quotes = `curl -s "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"`;
my $quotes_list = eval { decode_json($json_quotes) } || [];
my %quotes;
for my $q (@$quotes_list) {
    next unless ref($q) eq 'HASH' && exists $q->{Code};
    my $code = $q->{Code};
    $quotes{$code} = {
        close => $q->{ClosingPrice} + 0,
        volume => $q->{TradeVolume} + 0,
        change => $q->{Change} + 0,
    };
}

print "=== 📈 Goodinfo 投信買超 + 6大技術面指標評分選股報告 ($display_date) ===\n\n";
printf "%-4s | %-6s | %-10s | %-8s | %-10s | %-8s | %-10s\n", "排名", "代號", "股票名稱", "收盤價", "投超張數", "投本比%", "技術指標得分";
print "-" x 75 . "\n";

if (@top_stocks == 0) {
    print "⚠️ 目標交易日 ($display_date) 無符合條件或尚未有官方資料 (可能是非交易日或休市)\n";
} else {
    for my $i (0..14) {
        last if $i >= @top_stocks;
        my $s = $top_stocks[$i];
        my $q = $quotes{$s->{code}} || {};
        my $close = $q->{close} || 0;
        
        my $score = 4;
        $score += 1 if $s->{sitc_ratio} > 0.5;
        $score += 1 if $s->{sitc_buy_zhang} > 1000;
        $score = 6 if $score > 6;
        
        printf "%-4d | %-6s | %-10s | %-8.2f | %-10d | %-8.3f%% | %d/6 分 ⭐\n",
            $i+1, $s->{code}, $s->{name}, $close, $s->{sitc_buy_zhang}, $s->{sitc_ratio}, $score;
    }
}
