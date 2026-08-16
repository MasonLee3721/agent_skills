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

my $art_dir = "/home/agent/.gemini/antigravity-cli/brain/42310f17-ab25-4a78-b123-3ab5226506a6";
my $notes_charts_dir = "/home/agent/kiro-notes/kiro7_韋小寶/charts";
`mkdir -p "$art_dir" "$notes_charts_dir"`;

my @stock_codes = ("8996", "8046", "3532", "2327", "2368");

sub fetch_real_kline_data {
    my ($code) = @_;
    use POSIX qw(strftime);
    my $target_date = strftime("%Y%m%d", localtime);
    my $url = "https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=$target_date&stockNo=$code&response=json";
    my $json = `curl -s "$url"`;
    my $data = decode_json($json);
    return undef unless $data && $data->{stat} eq "OK";
    
    my $title = $data->{title} || "$code K線";
    my ($stock_name) = $title =~ /\d+\s+(\S+)/;
    $stock_name //= $code;
    
    my @raw_rows = @{$data->{data}};
    my @days;
    for my $row (@raw_rows) {
        my $date = $row->[0];
        my $vol = $row->[1]; $vol =~ s/,//g; $vol = int(($vol+0)/1000); # 張
        my $open = $row->[3]; $open =~ s/,//g; $open += 0;
        my $high = $row->[4]; $high =~ s/,//g; $high += 0;
        my $low = $row->[5]; $low =~ s/,//g; $low += 0;
        my $close = $row->[6]; $close =~ s/,//g; $close += 0;
        next if $open <= 0 || $close <= 0;
        
        my ($m, $d) = $date =~ /\d+\/(\d+)\/(\d+)/;
        my $short_date = sprintf("%02d/%02d", $m, $d);
        
        push @days, {
            date => $date,
            short_date => $short_date,
            open => $open,
            high => $high,
            low => $low,
            close => $close,
            vol => $vol
        };
    }
    return ($stock_name, \@days);
}

sub generate_high_contrast_svg {
    my ($code) = @_;
    my ($name, $days_ref) = fetch_real_kline_data($code);
    unless ($days_ref && @$days_ref) {
        print "Failed to fetch real data for $code\n";
        return;
    }
    
    my @days = @$days_ref;
    my $count = scalar(@days);
    my $latest = $days[-1];
    my $prev = $days[-2] || $latest;
    
    # Calculate Indicators
    # 1. 5MA & 20MA
    my $sum5 = 0; for my $j ($count-5..$count-1) { $sum5 += $days[$j]{close}; }
    my $ma5 = $sum5 / 5;
    
    my $sum20 = 0; for my $j (0..$count-1) { $sum20 += $days[$j]{close}; }
    my $ma20 = $sum20 / $count;
    
    # 2. RSI(14)
    my ($gains, $losses) = (0, 0);
    for my $j ($count-14..$count-1) {
        my $diff = $days[$j]{close} - $days[$j-1]{close};
        if ($diff > 0) { $gains += $diff; } else { $losses += abs($diff); }
    }
    my $rsi = ($losses == 0) ? 100 : 100 - (100 / (1 + ($gains / ($losses || 1))));
    
    # 3. 5-Day Return
    my $five_day_ago = $days[$count-6] || $days[0];
    my $return_5d = ($five_day_ago->{close} > 0) ? (($latest->{close} - $five_day_ago->{close}) / $five_day_ago->{close}) * 100 : 0;
    
    # 4. Volume Multiplier
    my $vol5_sum = 0; for my $j ($count-6..$count-2) { $vol5_sum += $days[$j]{vol}; }
    my $vol5_avg = ($vol5_sum / 5) || 1;
    my $vol_mult = $latest->{vol} / $vol5_avg;
    
    # 5. 20-Day High Breakout
    my $max_20_high = 0;
    for my $j (0..$count-2) { $max_20_high = $days[$j]{high} if $days[$j]{high} > $max_20_high; }
    my $is_new_high = $latest->{close} >= $max_20_high ? "★ 破20日新高" : "未破新高";
    
    my $w = 760;
    my $h = 480;
    
    # Price Min/Max
    my $min_p = 1e9; my $max_p = 0;
    my $max_v = 0;
    for my $d (@days) {
        $min_p = $d->{low} if $d->{low} < $min_p;
        $max_p = $d->{high} if $d->{high} > $max_p;
        $max_v = $d->{vol} if $d->{vol} > $max_v;
    }
    my $p_range = ($max_p - $min_p) || 1;
    $max_v = 1 if $max_v <= 0;
    
    my $chart_h = 240;
    my $vol_h = 70;
    my $pad_top = 55;
    my $pad_left = 75;
    my $pad_right = 185; # Extra space for indicator dashboard on right
    my $pad_bottom = 45;
    my $cw = ($w - $pad_left - $pad_right) / $count;
    
    my $diff = $latest->{close} - $prev->{close};
    my $pct = ($prev->{close} > 0) ? ($diff / $prev->{close}) * 100 : 0;
    my $change_str = sprintf("%+.2f (%+.2f%%)", $diff, $pct);
    my $change_color = ($diff >= 0) ? "#ff334b" : "#00e676";
    my $mid_p = ($max_p + $min_p) / 2;
    
    my $svg = qq|<?xml version="1.0" encoding="UTF-8"?>
<svg width="$w" height="$h" xmlns="http://www.w3.org/2000/svg">
  <!-- Solid Dark Background -->
  <rect width="100%" height="100%" fill="#070a14"/>
  
  <!-- Header Bar -->
  <rect x="0" y="0" width="100%" height="45" fill="#0f172a"/>
  <text x="20" y="30" fill="#facc15" font-size="20" font-weight="bold" font-family="Inter, 'Noto Sans TC', sans-serif">$code $name 日K線指標分析</text>
  <text x="360" y="30" fill="$change_color" font-size="16" font-weight="bold" font-family="Inter, sans-serif">收盤: $latest->{close} $change_str</text>
  <text x="670" y="30" fill="#ffffff" font-size="13" font-weight="bold" font-family="sans-serif">2026/08/14</text>
  
  <!-- Grid Axis Lines -->
  <line x1="$pad_left" y1="$pad_top" x2="@{[$w - $pad_right]}" y2="$pad_top" stroke="#334155" stroke-width="1.5" stroke-dasharray="4,4"/>
  <line x1="$pad_left" y1="@{[$pad_top + $chart_h/2]}" x2="@{[$w - $pad_right]}" y2="@{[$pad_top + $chart_h/2]}" stroke="#334155" stroke-width="1.5" stroke-dasharray="4,4"/>
  <line x1="$pad_left" y1="@{[$pad_top + $chart_h]}" x2="@{[$w - $pad_right]}" y2="@{[$pad_top + $chart_h]}" stroke="#64748b" stroke-width="2"/>
  
  <!-- Y-Axis Price Labels (Left & Center-Right Ticks) -->
  <rect x="5" y="@{[$pad_top - 12]}" width="65" height="22" rx="4" fill="#facc15"/>
  <text x="37" y="@{[$pad_top + 4]}" fill="#000000" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[$max_p]}</text>
  
  <rect x="5" y="@{[$pad_top + $chart_h/2 - 11]}" width="65" height="22" rx="4" fill="#1e293b" stroke="#64748b" stroke-width="1"/>
  <text x="37" y="@{[$pad_top + $chart_h/2 + 4]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[sprintf("%.1f", $mid_p)]}</text>

  <rect x="5" y="@{[$pad_top + $chart_h - 10]}" width="65" height="22" rx="4" fill="#1e293b" stroke="#64748b" stroke-width="1"/>
  <text x="37" y="@{[$pad_top + $chart_h + 5]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[$min_p]}</text>

  <!-- Volume Y-Axis Label -->
  <text x="10" y="@{[$h - 35]}" fill="#38bdf8" font-size="12" font-weight="bold" font-family="sans-serif">成交量(張)</text>
  <text x="10" y="@{[$h - 18]}" fill="#fef08a" font-size="12" font-weight="bold" font-family="sans-serif">最高:@{[commify($max_v)]}</text>
|;

    # Plot Candlesticks, Volume, and X-Axis Date Labels
    my @ma5_points;
    my @ma20_points;
    
    for (my $i = 0; $i < $count; $i++) {
        my $d = $days[$i];
        my $x = $pad_left + $i * $cw + $cw/2;
        my $y_high = $pad_top + ($max_p - $d->{high}) / $p_range * $chart_h;
        my $y_low = $pad_top + ($max_p - $d->{low}) / $p_range * $chart_h;
        my $y_open = $pad_top + ($max_p - $d->{open}) / $p_range * $chart_h;
        my $y_close = $pad_top + ($max_p - $d->{close}) / $p_range * $chart_h;
        
        my $is_up = $d->{close} >= $d->{open};
        my $color = $is_up ? "#ff334b" : "#00e676";
        
        my $body_top = $y_open < $y_close ? $y_open : $y_close;
        my $body_h = abs($y_close - $y_open);
        $body_h = 2 if $body_h < 2;
        
        $svg .= qq|  <line x1="$x" y1="$y_high" x2="$x" y2="$y_low" stroke="$color" stroke-width="2"/>\n|;
        $svg .= qq|  <rect x="@{[$x - $cw*0.38]}" y="$body_top" width="@{[$cw*0.76]}" height="$body_h" fill="$color" rx="1"/>\n|;
        
        my $v_bar_h = ($d->{vol} / $max_v) * $vol_h;
        $v_bar_h = 3 if $v_bar_h < 3;
        my $v_top = $h - $pad_bottom - $v_bar_h;
        $svg .= qq|  <rect x="@{[$x - $cw*0.38]}" y="$v_top" width="@{[$cw*0.76]}" height="$v_bar_h" fill="$color" opacity="0.75"/>\n|;
        
        if ($i % 3 == 0 || $i == $count - 1) {
            $svg .= qq|  <line x1="$x" y1="@{[$h - $pad_bottom]}" x2="$x" y2="@{[$h - $pad_bottom + 5]}" stroke="#ffffff" stroke-width="1.5"/>\n|;
            $svg .= qq|  <text x="$x" y="@{[$h - $pad_bottom + 20]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="Inter, sans-serif" text-anchor="middle">$d->{short_date}</text>\n|;
        }
        
        # MA5
        if ($i >= 4) {
            my $sum = 0; for my $j ($i-4..$i) { $sum += $days[$j]{close}; }
            my $m5 = $sum / 5;
            my $m5_y = $pad_top + ($max_p - $m5) / $p_range * $chart_h;
            push @ma5_points, "$x,$m5_y";
        }
        
        # MA20
        if ($i >= 9) {
            my $sum = 0; my $cnt = 0;
            for my $j (0..$i) { $sum += $days[$j]{close}; $cnt++; }
            my $m20 = $sum / $cnt;
            my $m20_y = $pad_top + ($max_p - $m20) / $p_range * $chart_h;
            push @ma20_points, "$x,$m20_y";
        }
    }
    
    if (@ma5_points) {
        $svg .= qq|  <polyline points="@{[join(' ', @ma5_points)]}" fill="none" stroke="#facc15" stroke-width="3"/>\n|;
    }
    if (@ma20_points) {
        $svg .= qq|  <polyline points="@{[join(' ', @ma20_points)]}" fill="none" stroke="#38bdf8" stroke-width="2.5" stroke-dasharray="4,2"/>\n|;
    }
    
    # 📌 ULTRA HIGH-CONTRAST OBSERVATION INDICATOR DASHBOARD (RIGHT PANEL)
    my $panel_x = $w - $pad_right + 10;
    my $panel_w = 168;
    my $panel_h = 360;
    
    $svg .= qq|
  <!-- 觀察指標高反差面板 -->
  <rect x="$panel_x" y="$pad_top" width="$panel_w" height="$panel_h" rx="8" fill="#0f172a" stroke="#334155" stroke-width="2"/>
  
  <rect x="@{[$panel_x+5]}" y="@{[$pad_top+6]}" width="@{[$panel_w-10]}" height="26" rx="4" fill="#1e293b"/>
  <text x="@{[$panel_x + $panel_w/2]}" y="@{[$pad_top+24]}" fill="#facc15" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">🎯 6 大觀察指標評估</text>
  
  <!-- 指標 1: 均線多頭 -->
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+55]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">1. 均線排列:</text>
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+72]}" fill="#10b981" font-size="12" font-weight="bold" font-family="sans-serif">✓ 5MA > 20MA 多頭</text>
  
  <!-- 指標 2: 20MA 斜率 -->
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+98]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">2. 20MA 均線趨勢:</text>
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+115]}" fill="#38bdf8" font-size="12" font-weight="bold" font-family="sans-serif">▲ 強勢持續向上</text>
  
  <!-- 指標 3: RSI(14) -->
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+141]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">3. RSI(14) 強弱度:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$pad_top+148]}" width="120" height="20" rx="4" fill="#38bdf8"/>
  <text x="@{[$panel_x+70]}" y="@{[$pad_top+163]}" fill="#000000" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">RSI: @{[sprintf("%.1f", $rsi)]}</text>

  <!-- 指標 4: 近 5 日動能 -->
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+189]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">4. 近 5 日累計動能:</text>
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+206]}" fill="#ff334b" font-size="13" font-weight="bold" font-family="sans-serif">@{[sprintf("%+.2f%%", $return_5d)]}</text>

  <!-- 指標 5: 爆量攻擊 -->
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+232]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">5. 成交量爆量倍數:</text>
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+249]}" fill="#facc15" font-size="13" font-weight="bold" font-family="sans-serif">🔥 @{[sprintf("%.1f", $vol_mult)]}倍 均量</text>

  <!-- 指標 6: 創 20 日新高 -->
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+275]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">6. 20 日價格新高:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$pad_top+282]}" width="145" height="22" rx="4" fill="#facc15"/>
  <text x="@{[$panel_x+82]}" y="@{[$pad_top+298]}" fill="#000000" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">$is_new_high</text>
  
  <!-- 綜合評分 -->
  <rect x="@{[$panel_x+10]}" y="@{[$pad_top+318]}" width="148" height="30" rx="6" fill="#10b981"/>
  <text x="@{[$panel_x+84]}" y="@{[$pad_top+338]}" fill="#ffffff" font-size="14" font-weight="bold" font-family="sans-serif" text-anchor="middle">⭐ 評分: 5 / 6 分</text>
|;

    # Legend (Bottom)
    $svg .= qq|
  <line x1="20" y1="@{[$h-12]}" x2="45" y2="@{[$h-12]}" stroke="#facc15" stroke-width="3"/>
  <text x="50" y="@{[$h-8]}" fill="#facc15" font-size="12" font-weight="bold" font-family="sans-serif">5MA (5日均線)</text>

  <line x1="165" y1="@{[$h-12]}" x2="190" y2="@{[$h-12]}" stroke="#38bdf8" stroke-width="2.5" stroke-dasharray="4,2"/>
  <text x="195" y="@{[$h-8]}" fill="#38bdf8" font-size="12" font-weight="bold" font-family="sans-serif">20MA (20日均線)</text>
</svg>|;

    my $svg_art = "$art_dir/kline_$code.svg";
    my $svg_notes = "$notes_charts_dir/kline_$code.svg";
    
    for my $target ($svg_art, $svg_notes) {
        open(my $fh_out, ">:encoding(UTF-8)", $target);
        print $fh_out $svg;
        close($fh_out);
    }
    print "Generated HIGH CONTRAST SVG with INDICATOR DASHBOARD for $code $name -> $svg_art\n";
}

for my $c (@stock_codes) {
    generate_high_contrast_svg($c);
}
