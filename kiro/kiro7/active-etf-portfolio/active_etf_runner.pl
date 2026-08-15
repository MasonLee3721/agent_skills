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

my $data_dir = "/home/agent/agent_skills/kiro/kiro7/active-etf-portfolio/data";
`mkdir -p "$data_dir"`;

my $today = `date +%Y%m%d`;
chomp($today);
my $dest = "$data_dir/active_etf_49YTW_$today.xlsx";

# 1. Download Excel
if (! -f $dest) {
    my $cmd = "curl -s -c /tmp/cookies.txt -b /tmp/cookies.txt -L -H \"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\" \"https://www.ezmoney.com.tw/ETF/Fund/AssetExcelNPOI?fundCode=49YTW\" -o \"$dest\"";
    system($cmd);
}

# 2. Parse Excel
sub parse_xlsx {
    my ($file) = @_;
    return {} unless -f $file;
    
    my $tmp_dir = "/tmp/unpack_" . rand(10000);
    `rm -rf "$tmp_dir" && mkdir -p "$tmp_dir" && unzip -q "$file" -d "$tmp_dir"`;
    
    my $str_file = "$tmp_dir/xl/sharedStrings.xml";
    my @strings;
    if (-f $str_file) {
        open(my $fh, "<:utf8", $str_file);
        my $xml = join("", <$fh>);
        close($fh);
        while ($xml =~ /<t[^>]*>(.*?)<\/t>/gs) {
            my $v = $1;
            $v =~ s/&lt;/</g; $v =~ s/&gt;/>/g; $v =~ s/&amp;/&/g;
            push @strings, $v;
        }
    }
    
    my $sheet_file = "$tmp_dir/xl/worksheets/sheet1.xml";
    return {} unless -f $sheet_file;
    open(my $fh_s, "<:utf8", $sheet_file);
    my $sheet_xml = join("", <$fh_s>);
    close($fh_s);
    
    my %data = (
        meta => {},
        holdings => []
    );
    
    my $in_stock_section = 0;
    while ($sheet_xml =~ /<row r="(\d+)"[^>]*>(.*?)<\/row>/gs) {
        my $r_xml = $2;
        my @cells;
        while ($r_xml =~ /<c r="([A-Z]+)\d+"([^>]*)>(.*?)<\/c>/gs) {
            my $attrs = $2;
            my $body = $3;
            my ($val) = $body =~ /<v>(.*?)<\/v>/s;
            $val //= "";
            if ($attrs =~ /t="s"/) {
                $val = $strings[$val] // $val;
            }
            push @cells, $val;
        }
        
        next unless @cells;
        if ($cells[0] =~ /資料日期/i) {
            $data{meta}{date} = $cells[0];
        } elsif ($cells[0] eq "淨資產" && @cells > 1) {
            $data{meta}{nav} = $cells[1];
        } elsif ($cells[0] eq "每單位淨值" && @cells > 1) {
            $data{meta}{nav_per_unit} = $cells[1];
        } elsif ($cells[0] eq "股票" && @cells == 1) {
            $in_stock_section = 1;
        } elsif ($in_stock_section) {
            if ($cells[0] eq "股票代號") { next; }
            last if $cells[0] =~ /項目|期貨/i;
            if (@cells >= 4) {
                my $code = $cells[0]; $code =~ s/\s+//g;
                my $name = $cells[1]; $name =~ s/\s+//g;
                my $shares = $cells[2]; $shares =~ s/,//g;
                my $weight = $cells[3];
                push @{$data{holdings}}, {
                    code => $code,
                    name => $name,
                    shares => $shares + 0,
                    weight => $weight
                };
            }
        }
    }
    `rm -rf "$tmp_dir"`;
    return \%data;
}

my $parsed = parse_xlsx($dest);
print "=== 00981A 統一台灣成長主動式ETF 每日持股狀況 ===\n";
print "資料日期: ", ($parsed->{meta}{date} || "未知"), "\n";
print "淨資產: ", ($parsed->{meta}{nav} || "未知"), "\n";
print "每單位淨值: ", ($parsed->{meta}{nav_per_unit} || "未知"), "\n\n";

print "=== 前 15 大持股明細 ===\n";
printf "%-4s | %-6s | %-12s | %-12s | %-8s\n", "序號", "股號", "股票名稱", "持股張數", "持股權重";
print "-" x 55 . "\n";

my $idx = 1;
for my $h (@{$parsed->{holdings}}) {
    last if $idx > 15;
    my $zhang = commify(int($h->{shares} / 1000));
    printf "%-4d | %-6s | %-12s | %-12s | %-8s\n", $idx, $h->{code}, $h->{name}, $zhang, $h->{weight};
    $idx++;
}
