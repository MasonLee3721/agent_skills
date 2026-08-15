#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;
use File::Basename;

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
        holdings => {},
        names => {}
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
                $data{holdings}{$code} = {
                    code => $code,
                    name => $name,
                    shares => $shares + 0,
                    weight => $weight
                };
                $data{names}{$code} = $name;
            }
        }
    }
    `rm -rf "$tmp_dir"`;
    return \%data;
}

# Find all Excel files sorted
my @excel_files = sort glob("$data_dir/active_etf_49YTW_*.xlsx");
my $curr_file = $excel_files[-1];
my $curr_data = parse_xlsx($curr_file);

print "=== 00981A 統一台灣成長主動式ETF 每日持股狀況 ===\n";
print "資料日期: ", ($curr_data->{meta}{date} || "未知"), "\n";
print "淨資產: ", ($curr_data->{meta}{nav} || "未知"), "\n";
print "每單位淨值: ", ($curr_data->{meta}{nav_per_unit} || "未知"), "\n\n";

# Compare with previous if available
if (@excel_files >= 2) {
    # Check if there is a file with different content
    my $prev_file = undef;
    for (my $i = scalar(@excel_files) - 2; $i >= 0; $i--) {
        $prev_file = $excel_files[$i];
        last;
    }
    
    if ($prev_file) {
        my $prev_data = parse_xlsx($prev_file);
        print "=== 📊 持股異動比對 [", basename($prev_file), " → ", basename($curr_file), "] ===\n";
        
        my %all_codes = map { $_ => 1 } (keys %{$prev_data->{holdings}}, keys %{$curr_data->{holdings}});
        my (@new_in, @out, @buy, @sell);
        
        for my $code (keys %all_codes) {
            my $p = $prev_data->{holdings}{$code}{shares} || 0;
            my $c = $curr_data->{holdings}{$code}{shares} || 0;
            my $name = $curr_data->{names}{$code} || $prev_data->{names}{$code} || $code;
            
            if ($p == 0 && $c > 0) {
                push @new_in, { code => $code, name => $name, diff => $c };
            } elsif ($p > 0 && $c == 0) {
                push @out, { code => $code, name => $name, diff => $p };
            } elsif ($c > $p) {
                push @buy, { code => $code, name => $name, diff => $c - $p };
            } elsif ($c < $p) {
                push @sell, { code => $code, name => $name, diff => $p - $c };
            }
        }
        
        if (!@new_in && !@out && !@buy && !@sell) {
            print "ℹ️ [現階段說明] 本次與上一同日備份檔案內容相同 (非交易日/尚未發布新持股)，暫無持股數量增減。\n";
        } else {
            if (@new_in) {
                print "[+] 新買進：\n";
                for my $r (@new_in) { print "   $r->{code} $r->{name}  +" . commify($r->{diff}) . " 股\n"; }
            }
            if (@buy) {
                print "[^] 加碼：\n";
                for my $r (sort { $b->{diff} <=> $a->{diff} } @buy) { print "   $r->{code} $r->{name}  +" . commify($r->{diff}) . " 股\n"; }
            }
            if (@sell) {
                print "[v] 減碼：\n";
                for my $r (sort { $b->{diff} <=> $a->{diff} } @sell) { print "   $r->{code} $r->{name}  -" . commify($r->{diff}) . " 股\n"; }
            }
            if (@out) {
                print "[-] 出清：\n";
                for my $r (@out) { print "   $r->{code} $r->{name}  -" . commify($r->{diff}) . " 股\n"; }
            }
        }
        print "==================================================\n\n";
    }
} else {
    print "ℹ️ [提示] 目前為首次建立持股歷史庫（僅有 1 份歷史檔），將在下一個交易日官方發布新 Excel 時自動比對異動！\n\n";
}
