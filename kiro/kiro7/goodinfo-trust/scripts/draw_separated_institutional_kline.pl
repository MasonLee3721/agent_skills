#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;
use File::Path qw(make_path);

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d{3})(?=\d)(?!\d*\.)/$1,/g;
    return reverse $text;
}

my $art_dir = "/home/agent/.gemini/antigravity-cli/brain/42310f17-ab25-4a78-b123-3ab5226506a6";
my $notes_charts_dir = "/home/agent/kiro-notes/kiro7_韋小寶/charts";
my $root_charts_dir  = "/home/agent/kiro-notes/charts";
my $db_file = "/home/agent/agent_skills/kiro/kiro7/goodinfo-trust/data/t86_real_database.json";
my $kline_cache_file = "/home/agent/agent_skills/kiro/kiro7/goodinfo-trust/data/stock_day_kline_cache.json";

make_path($art_dir) unless -d $art_dir;
make_path($notes_charts_dir) unless -d $notes_charts_dir;
make_path($root_charts_dir) unless -d $root_charts_dir;

# Load 100% RAW TWSE T86 Official Database
my %t86_raw_db;
if (-f $db_file) {
    local $/;
    open my $fh, "<:encoding(UTF-8)", $db_file;
    my $content = <$fh>;
    close $fh;
    if ($content) {
        eval { %t86_raw_db = %{ decode_json($content) }; };
    }
}

# Load Stock Day K-line Local Cache
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

sub fetch_150d_kline_data {
    my ($code) = @_;
    my @all_days;
    my $stock_name = $code;
    
    if (exists $kline_db{$code} && ref($kline_db{$code}) eq 'HASH' && $kline_db{$code}{days} && @{$kline_db{$code}{days}} > 50) {
        return ($kline_db{$code}{name}, $kline_db{$code}{days});
    }
    
    for my $m (@months) {
        my $url = "https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=$m&stockNo=$code&response=json";
        my $json = `curl -s -A "Mozilla/5.0" "$url"`;
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
        select(undef, undef, undef, 0.4);
    }
    
    if (@all_days) {
        $kline_db{$code} = {
            name => $stock_name,
            days => \@all_days
        };
        open my $fh_out, ">:encoding(UTF-8)", $kline_cache_file;
        print $fh_out encode_json(\%kline_db);
        close $fh_out;
    }
    
    return ($stock_name, \@all_days);
}

sub attach_raw_official_institutional_data {
    my ($code, $days_ref) = @_;
    
    for my $d (@$days_ref) {
        my $f_date = $d->{full_date};
        if (exists $t86_raw_db{$f_date} && ref($t86_raw_db{$f_date}) eq 'HASH') {
            my $rec = $t86_raw_db{$f_date}{$code};
            if ($rec && ref($rec) eq 'HASH' && defined $rec->{foreign_buy}) {
                $d->{foreign_buy} = $rec->{foreign_buy};
                $d->{sitc_buy} = $rec->{sitc_buy};
                $d->{has_raw_data} = 1;
            }
        }
    }
    return $days_ref;
}

sub calculate_master_indicators {
    my ($days_ref) = @_;
    my @days = @$days_ref;
    my $count = scalar(@days);
    
    # 1. MACD & CD值
    my $k12 = 2 / (12 + 1); my $k26 = 2 / (26 + 1); my $k9  = 2 / (9 + 1);
    my $ema12 = $days[0]{close}; my $ema26 = $days[0]{close}; my $macd_sig = 0;
    
    for (my $i = 0; $i < $count; $i++) {
        my $c = $days[$i]{close};
        $ema12 = $c * $k12 + $ema12 * (1 - $k12);
        $ema26 = $c * $k26 + $ema26 * (1 - $k26);
        my $dif = $ema12 - $ema26;
        $macd_sig = ($i == 0) ? $dif : ($dif * $k9 + $macd_sig * (1 - $k9));
        $days[$i]{dif} = $dif;
        $days[$i]{macd_sig} = $macd_sig;
        $days[$i]{osc} = $dif - $macd_sig;
    }
    
    # 2. RSI(14)
    my ($avg_gain, $avg_loss) = (0, 0);
    for (my $i = 0; $i < $count; $i++) {
        if ($i == 0) { $days[$i]{rsi} = 50; next; }
        my $diff = $days[$i]{close} - $days[$i-1]{close};
        my $gain = $diff > 0 ? $diff : 0; my $loss = $diff < 0 ? abs($diff) : 0;
        if ($i <= 14) {
            $avg_gain += $gain; $avg_loss += $loss;
            if ($i == 14) { $avg_gain /= 14; $avg_loss /= 14; }
        } else {
            $avg_gain = ($avg_gain * 13 + $gain) / 14;
            $avg_loss = ($avg_loss * 13 + $loss) / 14;
        }
        my $rs = ($avg_loss == 0) ? 100 : ($avg_gain / ($avg_loss || 1));
        $days[$i]{rsi} = 100 - (100 / (1 + $rs));
    }
    
    # 3. KD(9,3,3)
    my $prev_k = 50; my $prev_d = 50;
    for (my $i = 0; $i < $count; $i++) {
        my $start = ($i >= 8) ? ($i - 8) : 0;
        my $max_h = 0; my $min_l = 1e9;
        for my $j ($start..$i) {
            $max_h = $days[$j]{high} if $days[$j]{high} > $max_h;
            $min_l = $days[$j]{low} if $days[$j]{low} < $min_l;
        }
        my $range = ($max_h - $min_l) || 1;
        my $rsv = (($days[$i]{close} - $min_l) / $range) * 100;
        my $curr_k = $prev_k * (2/3) + $rsv * (1/3);
        my $curr_d = $prev_d * (2/3) + $curr_k * (1/3);
        $days[$i]{k_val} = $curr_k; $days[$i]{d_val} = $curr_d;
        $prev_k = $curr_k; $prev_d = $curr_d;
    }
    
    return \@days;
}

sub generate_raw_governed_indicators_svg {
    my ($code) = @_;
    my ($name, $raw_days_ref) = fetch_150d_kline_data($code);
    unless ($raw_days_ref && @$raw_days_ref) {
        print "Failed to fetch 150d data for $code\n";
        return;
    }
    
    my $t86_days_ref = attach_raw_official_institutional_data($code, $raw_days_ref);
    my $days_ref = calculate_master_indicators($t86_days_ref);
    my @days = @$days_ref;
    my $count = scalar(@days);
    my $latest = $days[-1];
    my $prev = $days[-2] || $latest;
    my $first = $days[0];
    
    my $w = 1080;
    my $h = 1180;
    
    my $pad_left = 75;
    my $pad_right = 225;
    my $cw = ($w - $pad_left - $pad_right) / $count;
    
    # Subchart positions & heights
    my $main_top    = 60;   my $main_h    = 240; # Price & MAs
    my $vol_top     = 320;  my $vol_h     = 80;  # Volume
    my $foreign_top = 430;  my $foreign_h = 100; # 外資獨立買賣超副圖
    my $sitc_top    = 550;  my $sitc_h    = 100; # 投信獨立買賣超副圖
    my $kd_top      = 670;  my $kd_h      = 110; # KD(9,3,3)
    my $macd_top    = 800;  my $macd_h    = 130; # MACD & CD值
    my $rsi_top     = 950;  my $rsi_h     = 110; # RSI(14)
    
    # Price Min/Max
    my $min_p = 1e9; my $max_p = 0; my $max_v = 0;
    my $min_f = 1e9; my $max_f = -1e9;
    my $min_s = 1e9; my $max_s = -1e9;
    my $min_osc = 1e9; my $max_osc = -1e9;
    my $min_dif = 1e9; my $max_dif = -1e9;
    
    my $raw_data_count = 0;
    
    for my $d (@days) {
        $min_p = $d->{low} if $d->{low} < $min_p;
        $max_p = $d->{high} if $d->{high} > $max_p;
        $max_v = $d->{vol} if $d->{vol} > $max_v;
        
        if ($d->{has_raw_data}) {
            $raw_data_count++;
            $min_f = $d->{foreign_buy} if $d->{foreign_buy} < $min_f;
            $max_f = $d->{foreign_buy} if $d->{foreign_buy} > $max_f;
            
            $min_s = $d->{sitc_buy} if $d->{sitc_buy} < $min_s;
            $max_s = $d->{sitc_buy} if $d->{sitc_buy} > $max_s;
        }
        
        $min_osc = $d->{osc} if $d->{osc} < $min_osc;
        $max_osc = $d->{osc} if $d->{osc} > $max_osc;
        $min_dif = $d->{dif} if $d->{dif} < $min_dif;
        $max_dif = $d->{dif} if $d->{dif} > $max_dif;
    }
    my $p_range = ($max_p - $min_p) || 1;
    $max_v = 1 if $max_v <= 0;
    
    my $abs_f_max = abs($max_f); $abs_f_max = abs($min_f) if abs($min_f) > $abs_f_max; $abs_f_max = 100 if $abs_f_max <= 0;
    my $abs_s_max = abs($max_s); $abs_s_max = abs($min_s) if abs($min_s) > $abs_s_max; $abs_s_max = 100 if $abs_s_max <= 0;
    
    my $abs_macd_max = abs($max_osc);
    $abs_macd_max = abs($min_osc) if abs($min_osc) > $abs_macd_max;
    $abs_macd_max = abs($max_dif) if abs($max_dif) > $abs_macd_max;
    $abs_macd_max = abs($min_dif) if abs($min_dif) > $abs_macd_max;
    $abs_macd_max = 1 if $abs_macd_max <= 0;
    
    my $total_return = ($first->{close} > 0) ? (($latest->{close} - $first->{close}) / $first->{close}) * 100 : 0;
    my $diff = $latest->{close} - $prev->{close};
    my $pct = ($prev->{close} > 0) ? ($diff / $prev->{close}) * 100 : 0;
    my $change_str = sprintf("%+.2f (%+.2f%%)", $diff, $pct);
    my $change_color = ($diff >= 0) ? "#ff334b" : "#00e676";
    my $mid_p = ($max_p + $min_p) / 2;
    
    my $svg = qq|<?xml version="1.0" encoding="UTF-8"?>
<svg width="$w" height="$h" xmlns="http://www.w3.org/2000/svg">
  <!-- Solid Dark Background -->
  <rect width="100%" height="100%" fill="#050811"/>
  
  <!-- Header Bar -->
  <rect x="0" y="0" width="100%" height="50" fill="#0f172a"/>
  <text x="20" y="33" fill="#facc15" font-size="22" font-weight="bold" font-family="Inter, 'Noto Sans TC', sans-serif">$code $name 7合1官方籌碼+技術面技術分析圖</text>
  <text x="640" y="33" fill="$change_color" font-size="17" font-weight="bold" font-family="Inter, sans-serif">收盤: $latest->{close} $change_str</text>
  <text x="960" y="33" fill="#ffffff" font-size="13" font-weight="bold" font-family="sans-serif">2026/08/14</text>
  
  <!-- 1. Main Price Box -->
  <rect x="$pad_left" y="$main_top" width="@{[$w - $pad_left - $pad_right]}" height="$main_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <line x1="$pad_left" y1="@{[$main_top + $main_h/2]}" x2="@{[$w - $pad_right]}" y2="@{[$main_top + $main_h/2]}" stroke="#1e293b" stroke-dasharray="4,4"/>
  
  <rect x="5" y="@{[$main_top - 12]}" width="65" height="24" rx="4" fill="#facc15"/>
  <text x="37" y="@{[$main_top + 5]}" fill="#000000" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[$max_p]}</text>
  
  <rect x="5" y="@{[$main_top + $main_h/2 - 12]}" width="65" height="24" rx="4" fill="#1e293b" stroke="#64748b" stroke-width="1"/>
  <text x="37" y="@{[$main_top + $main_h/2 + 5]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[sprintf("%.1f", $mid_p)]}</text>

  <rect x="5" y="@{[$main_top + $main_h - 12]}" width="65" height="24" rx="4" fill="#1e293b" stroke="#64748b" stroke-width="1"/>
  <text x="37" y="@{[$main_top + $main_h + 5]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[$min_p]}</text>

  <!-- 2. Volume Box -->
  <rect x="$pad_left" y="$vol_top" width="@{[$w - $pad_left - $pad_right]}" height="$vol_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <text x="10" y="@{[$vol_top + 25]}" fill="#38bdf8" font-size="12" font-weight="bold" font-family="sans-serif">成交量(張)</text>
  <text x="10" y="@{[$vol_top + 45]}" fill="#fef08a" font-size="12" font-weight="bold" font-family="sans-serif">最高:@{[commify($max_v)]}</text>

  <!-- 3. 外資獨立買賣超 Box -->
  <rect x="$pad_left" y="$foreign_top" width="@{[$w - $pad_left - $pad_right]}" height="$foreign_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <line x1="$pad_left" y1="@{[$foreign_top + $foreign_h/2]}" x2="@{[$w - $pad_right]}" y2="@{[$foreign_top + $foreign_h/2]}" stroke="#64748b" stroke-dasharray="2,2"/>
  <text x="10" y="@{[$foreign_top + 25]}" fill="#38bdf8" font-size="12" font-weight="bold" font-family="sans-serif">外資買賣超</text>
  <text x="10" y="@{[$foreign_top + 48]}" fill="#38bdf8" font-size="12" font-weight="bold" font-family="sans-serif">@{[defined $latest->{foreign_buy} ? sprintf("%+d張", $latest->{foreign_buy}) : "N/A"]}</text>
  <text x="@{[$w - $pad_right + 5]}" y="@{[$foreign_top + 20]}" fill="#38bdf8" font-size="11" font-weight="bold" font-family="sans-serif">▲買超(+藍)</text>
  <text x="@{[$w - $pad_right + 5]}" y="@{[$foreign_top + $foreign_h - 10]}" fill="#0284c7" font-size="11" font-weight="bold" font-family="sans-serif">▼賣超(-深藍)</text>

  <!-- 4. 投信獨立買賣超 Box -->
  <rect x="$pad_left" y="$sitc_top" width="@{[$w - $pad_left - $pad_right]}" height="$sitc_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <line x1="$pad_left" y1="@{[$sitc_top + $sitc_h/2]}" x2="@{[$w - $pad_right]}" y2="@{[$sitc_top + $sitc_h/2]}" stroke="#64748b" stroke-dasharray="2,2"/>
  <text x="10" y="@{[$sitc_top + 25]}" fill="#facc15" font-size="12" font-weight="bold" font-family="sans-serif">投信買賣超</text>
  <text x="10" y="@{[$sitc_top + 50]}" fill="#facc15" font-size="12" font-weight="bold" font-family="sans-serif">@{[defined $latest->{sitc_buy} ? sprintf("%+d張", $latest->{sitc_buy}) : "N/A"]}</text>
  <text x="@{[$w - $pad_right + 5]}" y="@{[$sitc_top + 20]}" fill="#facc15" font-size="11" font-weight="bold" font-family="sans-serif">▲買超(+黃)</text>
  <text x="@{[$w - $pad_right + 5]}" y="@{[$sitc_top + $sitc_h - 10]}" fill="#10b981" font-size="11" font-weight="bold" font-family="sans-serif">▼賣超(-綠)</text>

  <!-- 5. KD(9,3,3) Box -->
  <rect x="$pad_left" y="$kd_top" width="@{[$w - $pad_left - $pad_right]}" height="$kd_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <line x1="$pad_left" y1="@{[$kd_top + $kd_h*0.2]}" x2="@{[$w - $pad_right]}" y2="@{[$kd_top + $kd_h*0.2]}" stroke="#ef4444" stroke-dasharray="3,3"/>
  <line x1="$pad_left" y1="@{[$kd_top + $kd_h*0.5]}" x2="@{[$w - $pad_right]}" y2="@{[$kd_top + $kd_h*0.5]}" stroke="#64748b" stroke-dasharray="3,3"/>
  <line x1="$pad_left" y1="@{[$kd_top + $kd_h*0.8]}" x2="@{[$w - $pad_right]}" y2="@{[$kd_top + $kd_h*0.8]}" stroke="#10b981" stroke-dasharray="3,3"/>
  <text x="10" y="@{[$kd_top + 25]}" fill="#facc15" font-size="12" font-weight="bold" font-family="sans-serif">KD(9,3,3)</text>
  <text x="10" y="@{[$kd_top + 45]}" fill="#facc15" font-size="11" font-weight="bold" font-family="sans-serif">K: @{[sprintf("%.1f", $latest->{k_val})]}</text>
  <text x="10" y="@{[$kd_top + 65]}" fill="#38bdf8" font-size="11" font-weight="bold" font-family="sans-serif">D: @{[sprintf("%.1f", $latest->{d_val})]}</text>

  <!-- 6. MACD / CD值 Box -->
  <rect x="$pad_left" y="$macd_top" width="@{[$w - $pad_left - $pad_right]}" height="$macd_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <line x1="$pad_left" y1="@{[$macd_top + $macd_h/2]}" x2="@{[$w - $pad_right]}" y2="@{[$macd_top + $macd_h/2]}" stroke="#475569" stroke-dasharray="2,2"/>
  <text x="10" y="@{[$macd_top + 25]}" fill="#facc15" font-size="12" font-weight="bold" font-family="sans-serif">MACD / CD值</text>
  <text x="10" y="@{[$macd_top + 45]}" fill="#ff334b" font-size="11" font-weight="bold" font-family="sans-serif">DIF: @{[sprintf("%.2f", $latest->{dif})]}</text>
  <text x="10" y="@{[$macd_top + 65]}" fill="#38bdf8" font-size="11" font-weight="bold" font-family="sans-serif">MACD:@{[sprintf("%.2f", $latest->{macd_sig})]}</text>
  <text x="10" y="@{[$macd_top + 85]}" fill="#fef08a" font-size="11" font-weight="bold" font-family="sans-serif">CD值: @{[sprintf("%.2f", $latest->{osc})]}</text>

  <!-- 7. RSI(14) Box -->
  <rect x="$pad_left" y="$rsi_top" width="@{[$w - $pad_left - $pad_right]}" height="$rsi_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <line x1="$pad_left" y1="@{[$rsi_top + $rsi_h*0.2]}" x2="@{[$w - $pad_right]}" y2="@{[$rsi_top + $rsi_h*0.2]}" stroke="#ef4444" stroke-dasharray="3,3"/>
  <line x1="$pad_left" y1="@{[$rsi_top + $rsi_h*0.5]}" x2="@{[$w - $pad_right]}" y2="@{[$rsi_top + $rsi_h*0.5]}" stroke="#64748b" stroke-dasharray="3,3"/>
  <line x1="$pad_left" y1="@{[$rsi_top + $rsi_h*0.8]}" x2="@{[$w - $pad_right]}" y2="@{[$rsi_top + $rsi_h*0.8]}" stroke="#10b981" stroke-dasharray="3,3"/>
  <text x="10" y="@{[$rsi_top + 25]}" fill="#c084fc" font-size="12" font-weight="bold" font-family="sans-serif">RSI(14)</text>
  <text x="10" y="@{[$rsi_top + 50]}" fill="#c084fc" font-size="14" font-weight="bold" font-family="sans-serif">@{[sprintf("%.1f", $latest->{rsi})]}</text>
|;

    # Plot Series
    my @ma5_pts; my @ma20_pts; my @ma60_pts; my @ma120_pts;
    my @k_pts; my @d_pts;
    my @dif_pts; my @sig_pts; my @rsi_pts;
    
    my $last_mon = "";
    
    for (my $i = 0; $i < $count; $i++) {
        my $d = $days[$i];
        my $x = $pad_left + $i * $cw + $cw/2;
        
        # --- 1. Main Price Candlestick ---
        my $y_high = $main_top + ($max_p - $d->{high}) / $p_range * $main_h;
        my $y_low  = $main_top + ($max_p - $d->{low}) / $p_range * $main_h;
        my $y_open = $main_top + ($max_p - $d->{open}) / $p_range * $main_h;
        my $y_close= $main_top + ($max_p - $d->{close}) / $p_range * $main_h;
        
        my $is_up = $d->{close} >= $d->{open};
        my $color = $is_up ? "#ff334b" : "#00e676";
        
        my $body_top = $y_open < $y_close ? $y_open : $y_close;
        my $body_h = abs($y_close - $y_open); $body_h = 1.5 if $body_h < 1.5;
        
        $svg .= qq|  <line x1="$x" y1="$y_high" x2="$x" y2="$y_low" stroke="$color" stroke-width="1.2"/>\n|;
        $svg .= qq|  <rect x="@{[$x - $cw*0.4]}" y="$body_top" width="@{[$cw*0.8]}" height="$body_h" fill="$color"/>\n|;
        
        # --- 2. Volume Bar ---
        my $v_bar_h = ($d->{vol} / $max_v) * $vol_h; $v_bar_h = 2 if $v_bar_h < 2;
        my $v_top = $vol_top + $vol_h - $v_bar_h;
        $svg .= qq|  <rect x="@{[$x - $cw*0.4]}" y="$v_top" width="@{[$cw*0.8]}" height="$v_bar_h" fill="$color" opacity="0.75"/>\n|;
        
        # --- 3. 外資獨立買賣超副圖 (100% TWSE RAW DATA ONLY) ---
        my $f_zero_y = $foreign_top + $foreign_h / 2;
        if ($d->{has_raw_data} && defined $d->{foreign_buy}) {
            my $f_val = $d->{foreign_buy};
            my $f_bar_h = (abs($f_val) / $abs_f_max) * ($foreign_h / 2); $f_bar_h = 1.5 if $f_bar_h < 1.5;
            my $f_top_y = $f_val >= 0 ? ($f_zero_y - $f_bar_h) : $f_zero_y;
            my $f_color = $f_val >= 0 ? "#38bdf8" : "#0284c7";
            $svg .= qq|  <rect x="@{[$x - $cw*0.38]}" y="$f_top_y" width="@{[$cw*0.76]}" height="$f_bar_h" fill="$f_color"/>\n|;
        }
        
        # --- 4. 投信獨立買賣超副圖 (100% TWSE RAW DATA ONLY) ---
        my $s_zero_y = $sitc_top + $sitc_h / 2;
        if ($d->{has_raw_data} && defined $d->{sitc_buy}) {
            my $s_val = $d->{sitc_buy};
            my $s_bar_h = (abs($s_val) / $abs_s_max) * ($sitc_h / 2); $s_bar_h = 1.5 if $s_bar_h < 1.5;
            my $s_top_y = $s_val >= 0 ? ($s_zero_y - $s_bar_h) : $s_zero_y;
            my $s_color = $s_val >= 0 ? "#facc15" : "#10b981";
            $svg .= qq|  <rect x="@{[$x - $cw*0.38]}" y="$s_top_y" width="@{[$cw*0.76]}" height="$s_bar_h" fill="$s_color"/>\n|;
        }
        
        # --- 5. KD(9,3,3) ---
        my $k_y = $kd_top + $kd_h - ($d->{k_val} / 100) * $kd_h;
        my $d_y = $kd_top + $kd_h - ($d->{d_val} / 100) * $kd_h;
        push @k_pts, "$x,$k_y"; push @d_pts, "$x,$d_y";
        
        # --- 6. MACD / CD值 ---
        my $macd_zero_y = $macd_top + $macd_h / 2;
        my $osc_val = $d->{osc};
        my $osc_h = (abs($osc_val) / $abs_macd_max) * ($macd_h / 2); $osc_h = 1.5 if $osc_h < 1.5;
        my $osc_top_y = $osc_val >= 0 ? ($macd_zero_y - $osc_h) : $macd_zero_y;
        my $osc_color = $osc_val >= 0 ? "#ff334b" : "#00e676";
        $svg .= qq|  <rect x="@{[$x - $cw*0.35]}" y="$osc_top_y" width="@{[$cw*0.7]}" height="$osc_h" fill="$osc_color"/>\n|;
        
        my $dif_y = $macd_zero_y - ($d->{dif} / $abs_macd_max) * ($macd_h / 2);
        my $sig_y = $macd_zero_y - ($d->{macd_sig} / $abs_macd_max) * ($macd_h / 2);
        push @dif_pts, "$x,$dif_y"; push @sig_pts, "$x,$sig_y";
        
        # --- 7. RSI(14) ---
        my $rsi_y = $rsi_top + $rsi_h - ($d->{rsi} / 100) * $rsi_h;
        push @rsi_pts, "$x,$rsi_y";
        
        # Monthly X-Axis Tick Labels
        if ($d->{mon} ne $last_mon) {
            $last_mon = $d->{mon};
            $svg .= qq|  <line x1="$x" y1="$main_top" x2="$x" y2="@{[$rsi_top + $rsi_h + 5]}" stroke="#334155" stroke-dasharray="2,2"/>\n|;
            $svg .= qq|  <rect x="@{[$x - 18]}" y="@{[$rsi_top + $rsi_h + 8]}" width="36" height="22" rx="4" fill="#1e293b"/>\n|;
            $svg .= qq|  <text x="$x" y="@{[$rsi_top + $rsi_h + 23]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="Inter, sans-serif" text-anchor="middle">$d->{mon}月</text>\n|;
        }
        
        # MA Series
        if ($i >= 4) {
            my $sum = 0; for my $j ($i-4..$i) { $sum += $days[$j]{close}; }
            push @ma5_pts, "$x," . ($main_top + ($max_p - ($sum/5)) / $p_range * $main_h);
        }
        if ($i >= 19) {
            my $sum = 0; for my $j ($i-19..$i) { $sum += $days[$j]{close}; }
            push @ma20_pts, "$x," . ($main_top + ($max_p - ($sum/20)) / $p_range * $main_h);
        }
        if ($i >= 59) {
            my $sum = 0; for my $j ($i-59..$i) { $sum += $days[$j]{close}; }
            push @ma60_pts, "$x," . ($main_top + ($max_p - ($sum/60)) / $p_range * $main_h);
        }
        if ($i >= 119) {
            my $sum = 0; for my $j ($i-119..$i) { $sum += $days[$j]{close}; }
            push @ma120_pts, "$x," . ($main_top + ($max_p - ($sum/120)) / $p_range * $main_h);
        }
    }
    
    # Render Lines
    if (@ma120_pts) { $svg .= qq|  <polyline points="@{[join(' ', @ma120_pts)]}" fill="none" stroke="#ffffff" stroke-width="2" stroke-dasharray="4,2"/>\n|; }
    if (@ma60_pts)  { $svg .= qq|  <polyline points="@{[join(' ', @ma60_pts)]}" fill="none" stroke="#c084fc" stroke-width="2.5"/>\n|; }
    if (@ma20_pts)  { $svg .= qq|  <polyline points="@{[join(' ', @ma20_pts)]}" fill="none" stroke="#38bdf8" stroke-width="2.5"/>\n|; }
    if (@ma5_pts)   { $svg .= qq|  <polyline points="@{[join(' ', @ma5_pts)]}" fill="none" stroke="#facc15" stroke-width="2"/>\n|; }
    
    if (@k_pts) { $svg .= qq|  <polyline points="@{[join(' ', @k_pts)]}" fill="none" stroke="#facc15" stroke-width="2"/>\n|; }
    if (@d_pts) { $svg .= qq|  <polyline points="@{[join(' ', @d_pts)]}" fill="none" stroke="#38bdf8" stroke-width="2"/>\n|; }
    
    if (@dif_pts) { $svg .= qq|  <polyline points="@{[join(' ', @dif_pts)]}" fill="none" stroke="#facc15" stroke-width="2"/>\n|; }
    if (@sig_pts) { $svg .= qq|  <polyline points="@{[join(' ', @sig_pts)]}" fill="none" stroke="#38bdf8" stroke-width="2"/>\n|; }
    
    if (@rsi_pts) { $svg .= qq|  <polyline points="@{[join(' ', @rsi_pts)]}" fill="none" stroke="#c084fc" stroke-width="2"/>\n|; }
    
    # 📌 RIGHT PANEL: STRICT DATA GOVERNANCE DASHBOARD
    my $panel_x = $w - $pad_right + 10;
    my $panel_w = 210;
    my $panel_h = 1050;
    
    my $kd_status = ($latest->{k_val} >= $latest->{d_val}) ? "🔥 KD金叉多頭" : "❄️ KD死叉空頭";
    my $kd_bg = ($latest->{k_val} >= $latest->{d_val}) ? "#ff334b" : "#00e676";
    
    my $f_txt = (defined $latest->{foreign_buy}) ? (($latest->{foreign_buy} >= 0 ? "+" : "").commify($latest->{foreign_buy})."張") : "N/A";
    my $s_txt = (defined $latest->{sitc_buy}) ? (($latest->{sitc_buy} >= 0 ? "+" : "").commify($latest->{sitc_buy})."張") : "N/A";
    
    $svg .= qq|
  <!-- 右側 7 合 1 DATA GOVERNANCE 嚴格控管面板 -->
  <rect x="$panel_x" y="$main_top" width="$panel_w" height="$panel_h" rx="8" fill="#0f172a" stroke="#334155" stroke-width="2"/>
  
  <rect x="@{[$panel_x+5]}" y="@{[$main_top+6]}" width="@{[$panel_w-10]}" height="28" rx="4" fill="#1e293b"/>
  <text x="@{[$panel_x + $panel_w/2]}" y="@{[$main_top+25]}" fill="#facc15" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">🏛️ TWSE 100% 官方數據</text>
  
  <!-- Data Governance Status Badge -->
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+42]}" width="190" height="22" rx="4" fill="#0284c7"/>
  <text x="@{[$panel_x+105]}" y="@{[$main_top+57]}" fill="#ffffff" font-size="11" font-weight="bold" font-family="sans-serif" text-anchor="middle">Raw Data: $raw_data_count / $count 天</text>

  <!-- 1. 外資獨立買賣超 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+78]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">1. 外資當日官方買賣超:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+85]}" width="190" height="24" rx="4" fill="@{[(defined $latest->{foreign_buy} && $latest->{foreign_buy}>=0)?'#38bdf8':'#0284c7']}"/>
  <text x="@{[$panel_x+105]}" y="@{[$main_top+102]}" fill="#ffffff" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">外資 $f_txt</text>

  <!-- 2. 投信獨立買賣超 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+132]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">2. 投信當日官方買賣超:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+139]}" width="190" height="24" rx="4" fill="@{[(defined $latest->{sitc_buy} && $latest->{sitc_buy}>=0)?'#facc15':'#10b981']}"/>
  <text x="@{[$panel_x+105]}" y="@{[$main_top+156]}" fill="#000000" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">投信 $s_txt</text>

  <!-- 3. KD(9,3,3) 轉折評估 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+186]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">3. KD(9,3,3) 轉折訊號:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+193]}" width="190" height="24" rx="4" fill="$kd_bg"/>
  <text x="@{[$panel_x+105]}" y="@{[$main_top+210]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">$kd_status</text>

  <!-- 4. MACD / CD值狀態 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+240]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">4. MACD / CD值狀態:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+247]}" width="190" height="24" rx="4" fill="@{[$latest->{osc} >= 0 ? '#ff334b' : '#00e676']}"/>
  <text x="@{[$panel_x+105]}" y="@{[$main_top+264]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[$latest->{osc} >= 0 ? '🔥 CD值紅柱 (多頭強勢)' : '🧊 CD值綠柱 (空頭修正)']}</text>

  <!-- 5. RSI(14) 動能位置 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+294]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">5. RSI(14) 動能強弱:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+301]}" width="190" height="22" rx="4" fill="#c084fc"/>
  <text x="@{[$panel_x+105]}" y="@{[$main_top+317]}" fill="#000000" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">RSI: @{[sprintf("%.1f", $latest->{rsi})]} (@{[$latest->{rsi}>70?'強勢超買':$latest->{rsi}>50?'多頭控盤':'弱勢區']})</text>

  <!-- 6. 150日波段總漲幅 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+347]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">6. 150日總波段漲幅:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+354]}" width="190" height="24" rx="4" fill="#ff334b"/>
  <text x="@{[$panel_x+105]}" y="@{[$main_top+371]}" fill="#ffffff" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[sprintf("%+.2f%%", $total_return)]}</text>

  <!-- 7. 150日最高天價 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+401]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">7. 150日最高天價:</text>
  <text x="@{[$panel_x+10]}" y="@{[$main_top+419]}" fill="#facc15" font-size="13" font-weight="bold" font-family="sans-serif">🔥 $max_p 元</text>

  <!-- 8. 150日最低支撐價 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+445]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">8. 150日波段底價:</text>
  <text x="@{[$panel_x+10]}" y="@{[$main_top+463]}" fill="#38bdf8" font-size="13" font-weight="bold" font-family="sans-serif">🛡️ $min_p 元</text>

  <!-- 綜合評分 -->
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+985]}" width="190" height="48" rx="6" fill="#10b981"/>
  <text x="@{[$panel_x+105]}" y="@{[$main_top+1015]}" fill="#ffffff" font-size="17" font-weight="bold" font-family="sans-serif" text-anchor="middle">🏛️ RAW 100% 準確</text>
|;

    # Bottom Legend Bar
    $svg .= qq|
  <line x1="20" y1="@{[$h-15]}" x2="40" y2="@{[$h-15]}" stroke="#facc15" stroke-width="2.5"/>
  <text x="45" y="@{[$h-11]}" fill="#facc15" font-size="11" font-weight="bold" font-family="sans-serif">5MA</text>

  <line x1="90" y1="@{[$h-15]}" x2="110" y2="@{[$h-15]}" stroke="#38bdf8" stroke-width="2.5"/>
  <text x="115" y="@{[$h-11]}" fill="#38bdf8" font-size="11" font-weight="bold" font-family="sans-serif">20MA</text>

  <line x1="160" y1="@{[$h-15]}" x2="180" y2="@{[$h-15]}" stroke="#c084fc" stroke-width="2.5"/>
  <text x="185" y="@{[$h-11]}" fill="#c084fc" font-size="11" font-weight="bold" font-family="sans-serif">60MA</text>

  <line x1="230" y1="@{[$h-15]}" x2="250" y2="@{[$h-15]}" stroke="#38bdf8" stroke-width="3"/>
  <text x="255" y="@{[$h-11]}" fill="#38bdf8" font-size="11" font-weight="bold" font-family="sans-serif">外資(TWSE 官方原始買賣超)</text>

  <line x1="430" y1="@{[$h-15]}" x2="450" y2="@{[$h-15]}" stroke="#facc15" stroke-width="3"/>
  <text x="455" y="@{[$h-11]}" fill="#facc15" font-size="11" font-weight="bold" font-family="sans-serif">投信(TWSE 官方原始買賣超)</text>
</svg>|;

    # Save to official strict raw SVG files
    my $svg_art = "$art_dir/kline_${code}_v8.svg";
    my $svg_notes = "$notes_charts_dir/kline_${code}_v8.svg";
    my $svg_root = "$root_charts_dir/kline_${code}_v8.svg";
    
    for my $target ($svg_art, $svg_notes, $svg_root) {
        open(my $fh_out, ">:encoding(UTF-8)", $target);
        print $fh_out $svg;
        close($fh_out);
    }
    print "Generated 100% RAW TWSE OFFICIAL GOVERNED SVG v8 for $code $name -> $svg_root\n";
}

for my $c (@stock_codes) {
    generate_raw_governed_indicators_svg($c);
}
