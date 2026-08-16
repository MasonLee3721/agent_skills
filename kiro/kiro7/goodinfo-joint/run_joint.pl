#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;

use POSIX qw(strftime);

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

# 動態計算目標交易日
sub get_target_date {
    if (@ARGV && $ARGV[0] =~ /^\d{8}$/) {
        return $ARGV[0];
    }
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    if ($wday == 6) { # 週六 -> 往前移至週五
        ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time - 86400);
    } elsif ($wday == 0) { # 週日 -> 往前移至週五
        ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time - 172800);
    }
    return strftime("%Y%m%d", $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
}

my $target_date = get_target_date();
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

# 2. Fetch TWSE T86
my $json_t86 = `curl -s "https://www.twse.com.tw/rwd/zh/fund/T86?response=json&date=$target_date&selectType=ALLBUT0999"`;
my $t86_data = eval { decode_json($json_t86) } || {};

my @joint_list;
if ($t86_data && ref($t86_data) eq 'HASH' && $t86_data->{data} && ref($t86_data->{data}) eq 'ARRAY') {
    for my $row (@{$t86_data->{data}}) {
        my $code = $row->[0]; $code =~ s/\s+//g if defined $code;
        next unless defined $code && exists $capital{$code};
        
        my $name = $row->[1]; $name =~ s/\s+//g if defined $name;
        my $foreign_buy = $row->[4]; $foreign_buy =~ s/,//g if defined $foreign_buy;
        my $sitc_buy = $row->[10]; $sitc_buy =~ s/,//g if defined $sitc_buy;
        my $total_buy = $row->[18]; $total_buy =~ s/,//g if defined $total_buy;
        
        my $shares = $capital{$code}->{shares};
        next if !defined $foreign_buy || !defined $sitc_buy || $shares <= 0;
        
        my $sitc_pct = ($sitc_buy / $shares) * 100;
        my $foreign_pct = ($foreign_buy / $shares) * 100;
        my $total_pct = ($total_buy / $shares) * 100;
        
        if ($sitc_pct > 0.05 && $foreign_pct > 0.1) {
            push @joint_list, {
                code => $code,
                name => $name,
                shares_zhang => int($shares / 1000),
                sitc_buy_zhang => int($sitc_buy / 1000),
                sitc_pct => $sitc_pct,
                foreign_buy_zhang => int($foreign_buy / 1000),
                foreign_pct => $foreign_pct,
                total_buy_zhang => int($total_buy / 1000),
                total_pct => $total_pct,
            };
        }
    }
}

@joint_list = sort { $b->{foreign_pct} <=> $a->{foreign_pct} } @joint_list;

print "=== 📊 $display_date 上市股票 外資與投信法人同買強勢榜 ===\n";
printf "%-4s | %-6s | %-10s | %-12s | %-12s | %-10s\n", "名次", "代號", "股票名稱", "投信買超(張/%)", "外資買超(張/%)", "法人合計%";
print "-" x 70 . "\n";

if (@joint_list == 0) {
    print "⚠️ 目標交易日 ($display_date) 無符合條件或尚未有官方資料 (可能是非交易日或休市)\n";
} else {
    for my $i (0..9) {
        last if $i >= @joint_list;
        my $r = $joint_list[$i];
        printf "%-4d | %-6s | %-10s | %d (+%.2f%%) | %d (+%.2f%%) | +%.2f%%\n",
            $i+1, $r->{code}, $r->{name}, $r->{sitc_buy_zhang}, $r->{sitc_pct}, $r->{foreign_buy_zhang}, $r->{foreign_pct}, $r->{total_pct};
    }
}
