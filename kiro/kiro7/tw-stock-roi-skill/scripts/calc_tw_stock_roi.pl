#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

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
my $date_str = $t86_data->{date} || "最新交易日";

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

print "=== 交易日期: $date_str ===\n\n";
print "=== 上市股票 投信買超投本比 TOP 15 ===\n";
printf "%-4s | %-6s | %-12s | %-12s | %-12s | %-10s\n", "名次", "代號", "股票名稱", "發行張數", "投信買超(張)", "投本比(%)";
print "-" x 70 . "\n";
for my $i (0..14) {
    last if $i >= @buy_top;
    my $r = $buy_top[$i];
    printf "%-4d | %-6s | %-12s | %-12d | %-12d | %-10.3f%%\n",
        $i + 1, $r->{code}, $r->{name}, $r->{shares_zhang}, $r->{sitc_buy_zhang}, $r->{sitc_ratio};
}

print "\n=== 上市股票 投信賣超投本比 TOP 15 ===\n";
printf "%-4s | %-6s | %-12s | %-12s | %-12s | %-10s\n", "名次", "代號", "股票名稱", "發行張數", "投信賣超(張)", "投本比(%)";
print "-" x 70 . "\n";
for my $i (0..14) {
    last if $i >= @sell_top;
    my $r = $sell_top[$i];
    printf "%-4d | %-6s | %-12s | %-12d | %-12d | %-10.3f%%\n",
        $i + 1, $r->{code}, $r->{name}, $r->{shares_zhang}, $r->{sitc_buy_zhang}, $r->{sitc_ratio};
}
