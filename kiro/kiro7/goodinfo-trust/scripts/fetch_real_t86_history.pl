#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $db_dir = "/home/agent/agent_skills/kiro/kiro7/goodinfo-trust/data";
`mkdir -p "$db_dir"`;
my $db_file = "$db_dir/t86_real_database.json";

my %db;
if (-f $db_file) {
    local $/;
    open my $fh, "<:encoding(UTF-8)", $db_file;
    my $content = <$fh>;
    close $fh;
    if ($content) {
        eval { %db = %{ decode_json($content) }; };
    }
}

my @stock_codes = ("8996", "8046", "3532", "2327", "2368");
my %targets_map = map { $_ => 1 } @stock_codes;

my @months = ("20260101", "20260201", "20260301", "20260401", "20260501", "20260601", "20260701", "20260801");
my %trade_dates_map;

for my $m (@months) {
    my $url = "https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=$m&stockNo=2330&response=json";
    my $json = `curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$url"`;
    my $data = eval { decode_json($json) };
    if ($data && $data->{stat} eq "OK" && $data->{data}) {
        for my $r (@{$data->{data}}) {
            my ($y, $mon, $d) = $r->[0] =~ /(\d+)\/(\d+)\/(\d+)/;
            my $full_date = sprintf("%04d%02d%02d", $y + 1911, $mon, $d);
            $trade_dates_map{$full_date} = 1;
        }
    }
    sleep(1);
}

my @trade_dates = sort keys %trade_dates_map;
print "Total trading dates found in 2026: " . scalar(@trade_dates) . "\n";

my $fetched_count = 0;
for my $date (@trade_dates) {
    # Skip if valid data already stored
    if (exists $db{$date} && ref($db{$date}) eq 'HASH' && !exists $db{$date}{status}) {
        my $has_all = 1;
        for my $c (@stock_codes) {
            if (!exists $db{$date}{$c} || !defined $db{$date}{$c}{foreign_buy}) {
                $has_all = 0; last;
            }
        }
        if ($has_all) {
            next;
        }
    }
    
    print "Fetching 100% RAW TWSE T86 for date: $date...\n";
    my $url = "https://www.twse.com.tw/rwd/zh/fund/T86?response=json&date=$date&selectType=ALLBUT0999";
    my $json = `curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$url"`;
    my $data = eval { decode_json($json) };
    
    my %day_record;
    if ($data && $data->{stat} eq "OK" && $data->{data}) {
        for my $r (@{$data->{data}}) {
            my $code = $r->[0]; $code =~ s/\s+//g; $code =~ s/\*//g;
            if ($targets_map{$code}) {
                my $foreign = $r->[4]; $foreign =~ s/,//g; $foreign = int(($foreign+0)/1000);
                my $sitc = $r->[10]; $sitc =~ s/,//g; $sitc = int(($sitc+0)/1000);
                $day_record{$code} = {
                    foreign_buy => $foreign,
                    sitc_buy => $sitc,
                    raw => 1
                };
            }
        }
        $db{$date} = \%day_record;
        $fetched_count++;
        
        open my $fh_out, ">:encoding(UTF-8)", $db_file;
        print $fh_out encode_json(\%db);
        close $fh_out;
        print "Saved $date data for " . scalar(keys %day_record) . " stocks.\n";
    } else {
        print "TWSE T86 returned non-OK for $date: " . ($data ? $data->{stat} : "null/blocked") . "\n";
    }
    
    sleep(3); # 3-second polite delay per TWSE rate limit guidelines
}

print "TWSE T86 Raw Database backfill complete!\n";
