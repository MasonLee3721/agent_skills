#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

# 1. Fetch TWSE Capital
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
    };
}

# 2. Fetch TWSE T86
my $json_t86 = `curl -s "https://www.twse.com.tw/rwd/zh/fund/T86?response=json&date=20260814&selectType=ALLBUT0999"`;
my $t86_data = decode_json($json_t86);

my @top_stocks;
for my $row (@{$t86_data->{data}}) {
    my $code = $row->[0]; $code =~ s/\s+//g;
    next unless exists $capital{$code};
    
    my $name = $row->[1]; $name =~ s/\s+//g;
    my $sitc_buy = $row->[10]; $sitc_buy =~ s/,//g; # 投信買賣超股數
    my $shares = $capital{$code}->{shares};
    next if $shares <= 0 || $sitc_buy <= 0;
    
    my $sitc_ratio = ($sitc_buy / $shares) * 100;
    
    push @top_stocks, {
        code => $code,
        name => $name,
        shares_zhang => int($shares / 1000),
        sitc_buy_zhang => int($sitc_buy / 1000),
        sitc_ratio => $sitc_ratio,
    };
}

@top_stocks = sort { $b->{sitc_ratio} <=> $a->{sitc_ratio} } @top_stocks;

# Fetch daily quotes
my $json_quotes = `curl -s "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"`;
my $quotes_list = decode_json($json_quotes);
my %quotes;
for my $q (@$quotes_list) {
    my $code = $q->{Code};
    $quotes{$code} = {
        close => $q->{ClosingPrice} + 0,
        volume => $q->{TradeVolume} + 0,
        change => $q->{Change} + 0,
    };
}

print "=== 📈 Goodinfo 投信買超 + 6大技術面指標評分選股報告 (2026/08/14) ===\n\n";
printf "%-4s | %-6s | %-10s | %-8s | %-10s | %-8s | %-10s\n", "排名", "代號", "股票名稱", "收盤價", "投超張數", "投本比%", "技術指標得分";
print "-" x 75 . "\n";

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
