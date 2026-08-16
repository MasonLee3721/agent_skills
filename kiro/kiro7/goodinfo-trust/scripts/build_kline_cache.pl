#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;
use File::Path qw(make_path);

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $db_dir = "/home/agent/agent_skills/kiro/kiro7/goodinfo-trust/data";
make_path($db_dir) unless -d $db_dir;
my $kline_cache_file = "$db_dir/stock_day_kline_cache.json";

my %kline_db;
if (-f $kline_cache_file) {
    local $/;
    open my $fh, "<:encoding(UTF-8)", $kline_cache_file;
    my $content = <$fh>;
    close $fh;
    if ($content) {
        eval { %kline_db = %{ decode_json($content) }; };
    }
}

my @stock_codes = ("8996", "8046", "3532", "2327", "2368", "6442");
my @months = ("20260101", "20260201", "20260301", "20260401", "20260501", "20260601", "20260701", "20260801");

for my $code (@stock_codes) {
    if (exists $kline_db{$code} && ref($kline_db{$code}) eq 'HASH' && $kline_db{$code}{days} && @{$kline_db{$code}{days}} > 100) {
        print "Stock $code already has " . scalar(@{$kline_db{$code}{days}}) . " cached days.\n";
        next;
    }
    
    print "Fetching complete 150d K-line data for $code...\n";
    my @all_days;
    my $stock_name = $code;
    
    for my $m (@months) {
        my $url = "https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=$m&stockNo=$code&response=json";
        my $json = `curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$url"`;
        my $data = eval { decode_json($json) };
        if ($data && $data->{stat} eq "OK" && $data->{data}) {
            my $title = $data->{title} || "";
            if ($title =~ /\d+\s+(\S+)/) { $stock_name = $1; }
            for my $r (@{$data->{data}}) {
                my $vol = $r->[1]; $vol =~ s/,//g; $vol = int(($vol+0)/1000); # 張
                my $open = $r->[3]; $open =~ s/,//g; $open += 0;
                my $high = $r->[4]; $high =~ s/,//g; $high += 0;
                my $low = $r->[5]; $low =~ s/,//g; $low += 0;
                my $close = $r->[6]; $close =~ s/,//g; $close += 0;
                next if $open <= 0 || $close <= 0;
                
                my ($year, $mon, $day) = $r->[0] =~ /(\d+)\/(\d+)\/(\d+)/;
                my $full_date = sprintf("%04d%02d%02d", $year + 1911, $mon, $day);
                my $short_date = sprintf("%02d/%02d", $mon, $day);
                
                push @all_days, {
                    date => $r->[0],
                    full_date => $full_date,
                    mon => $mon,
                    short_date => $short_date,
                    open => $open,
                    high => $high,
                    low => $low,
                    close => $close,
                    vol => $vol,
                    foreign_buy => undef,
                    sitc_buy => undef,
                    has_raw_data => 0,
                };
            }
        }
        sleep(1);
    }
    
    if (@all_days) {
        $kline_db{$code} = {
            name => $stock_name,
            days => \@all_days
        };
        open my $fh_out, ">:encoding(UTF-8)", $kline_cache_file;
        print $fh_out encode_json(\%kline_db);
        close $fh_out;
        print "Saved " . scalar(@all_days) . " days for $code ($stock_name) to cache.\n";
    }
}

print "K-line cache build complete!\n";
