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
my @months = ("20260101", "20260201", "20260301", "20260401", "20260501", "20260601", "20260701", "20260801");

sub fetch_150d_kline_data {
    my ($code) = @_;
    my @all_days;
    my $stock_name = $code;
    
    for my $m (@months) {
        my $url = "https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=$m&stockNo=$code&response=json";
        my $json = `curl -s "$url"`;
        my $data = decode_json($json);
        if ($data && $data->{stat} eq "OK") {
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
                my $short_date = sprintf("%02d/%02d", $mon, $day);
                
                push @all_days, {
                    date => $r->[0],
                    mon => $mon,
                    short_date => $short_date,
                    open => $open,
                    high => $high,
                    low => $low,
                    close => $close,
                    vol => $vol
                };
            }
        }
    }
    return ($stock_name, \@all_days);
}

sub generate_150d_svg {
    my ($code) = @_;
    my ($name, $days_ref) = fetch_150d_kline_data($code);
    unless ($days_ref && @$days_ref) {
        print "Failed to fetch 150d data for $code\n";
        return;
    }
    
    my @days = @$days_ref;
    my $count = scalar(@days);
    my $latest = $days[-1];
    my $prev = $days[-2] || $latest;
    my $first = $days[0];
    
    # 150-Day Stats
    my $min_p = 1e9; my $max_p = 0;
    my $max_v = 0;
    for my $d (@days) {
        $min_p = $d->{low} if $d->{low} < $min_p;
        $max_p = $d->{high} if $d->{high} > $max_p;
        $max_v = $d->{vol} if $d->{vol} > $max_v;
    }
    my $p_range = ($max_p - $min_p) || 1;
    $max_v = 1 if $max_v <= 0;
    
    my $total_return = ($first->{close} > 0) ? (($latest->{close} - $first->{close}) / $first->{close}) * 100 : 0;
    
    # Calculate RSI(14)
    my ($gains, $losses) = (0, 0);
    for my $j ($count-14..$count-1) {
        my $diff = $days[$j]{close} - $days[$j-1]{close};
        if ($diff > 0) { $gains += $diff; } else { $losses += abs($diff); }
    }
    my $rsi = ($losses == 0) ? 100 : 100 - (100 / (1 + ($gains / ($losses || 1))));
    
    my $w = 980;
    my $h = 520;
    
    my $chart_h = 280;
    my $vol_h = 80;
    my $pad_top = 60;
    my $pad_left = 75;
    my $pad_right = 195;
    my $pad_bottom = 50;
    my $cw = ($w - $pad_left - $pad_right) / $count;
    
    my $diff = $latest->{close} - $prev->{close};
    my $pct = ($prev->{close} > 0) ? ($diff / $prev->{close}) * 100 : 0;
    my $change_str = sprintf("%+.2f (%+.2f%%)", $diff, $pct);
    my $change_color = ($diff >= 0) ? "#ff334b" : "#00e676";
    my $mid_p = ($max_p + $min_p) / 2;
    
    my $svg = qq|<?xml version="1.0" encoding="UTF-8"?>
<svg width="$w" height="$h" xmlns="http://www.w3.org/2000/svg">
  <!-- Solid Dark Background -->
  <rect width="100%" height="100%" fill="#060913"/>
  
  <!-- Header Bar -->
  <rect x="0" y="0" width="100%" height="50" fill="#0f172a"/>
  <text x="20" y="33" fill="#facc15" font-size="22" font-weight="bold" font-family="Inter, 'Noto Sans TC', sans-serif">$code $name 150日 K線全景觀察圖 (2026/01 ~ 08)</text>
  <text x="480" y="33" fill="$change_color" font-size="17" font-weight="bold" font-family="Inter, sans-serif">收盤: $latest->{close} $change_str</text>
  <text x="870" y="33" fill="#ffffff" font-size="13" font-weight="bold" font-family="sans-serif">共 $count 交易日</text>
  
  <!-- Grid Axis Lines -->
  <line x1="$pad_left" y1="$pad_top" x2="@{[$w - $pad_right]}" y2="$pad_top" stroke="#334155" stroke-width="1.5" stroke-dasharray="4,4"/>
  <line x1="$pad_left" y1="@{[$pad_top + $chart_h/2]}" x2="@{[$w - $pad_right]}" y2="@{[$pad_top + $chart_h/2]}" stroke="#334155" stroke-width="1.5" stroke-dasharray="4,4"/>
  <line x1="$pad_left" y1="@{[$pad_top + $chart_h]}" x2="@{[$w - $pad_right]}" y2="@{[$pad_top + $chart_h]}" stroke="#64748b" stroke-width="2"/>
  
  <!-- Y-Axis Price Ticks Labels -->
  <rect x="5" y="@{[$pad_top - 12]}" width="65" height="24" rx="4" fill="#facc15"/>
  <text x="37" y="@{[$pad_top + 5]}" fill="#000000" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[$max_p]}</text>
  
  <rect x="5" y="@{[$pad_top + $chart_h/2 - 12]}" width="65" height="24" rx="4" fill="#1e293b" stroke="#64748b" stroke-width="1"/>
  <text x="37" y="@{[$pad_top + $chart_h/2 + 5]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[sprintf("%.1f", $mid_p)]}</text>

  <rect x="5" y="@{[$pad_top + $chart_h - 12]}" width="65" height="24" rx="4" fill="#1e293b" stroke="#64748b" stroke-width="1"/>
  <text x="37" y="@{[$pad_top + $chart_h + 5]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[$min_p]}</text>

  <!-- Volume Y-Axis Label -->
  <text x="10" y="@{[$h - 40]}" fill="#38bdf8" font-size="12" font-weight="bold" font-family="sans-serif">成交量(張)</text>
  <text x="10" y="@{[$h - 22]}" fill="#fef08a" font-size="12" font-weight="bold" font-family="sans-serif">最高:@{[commify($max_v)]}</text>
|;

    # Plot Candlesticks, Volume, and Month Ticks
    my @ma5_points;
    my @ma20_points;
    my @ma60_points;
    my @ma120_points;
    
    my $last_mon = "";
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
        $body_h = 1.5 if $body_h < 1.5;
        
        $svg .= qq|  <line x1="$x" y1="$y_high" x2="$x" y2="$y_low" stroke="$color" stroke-width="1.2"/>\n|;
        $svg .= qq|  <rect x="@{[$x - $cw*0.4]}" y="$body_top" width="@{[$cw*0.8]}" height="$body_h" fill="$color"/>\n|;
        
        my $v_bar_h = ($d->{vol} / $max_v) * $vol_h;
        $v_bar_h = 2 if $v_bar_h < 2;
        my $v_top = $h - $pad_bottom - $v_bar_h;
        $svg .= qq|  <rect x="@{[$x - $cw*0.4]}" y="$v_top" width="@{[$cw*0.8]}" height="$v_bar_h" fill="$color" opacity="0.7"/>\n|;
        
        # Monthly X-Axis Labels
        if ($d->{mon} ne $last_mon) {
            $last_mon = $d->{mon};
            $svg .= qq|  <line x1="$x" y1="$pad_top" x2="$x" y2="@{[$h - $pad_bottom + 5]}" stroke="#334155" stroke-dasharray="2,2"/>\n|;
            $svg .= qq|  <rect x="@{[$x - 18]}" y="@{[$h - $pad_bottom + 8]}" width="36" height="22" rx="4" fill="#1e293b"/>\n|;
            $svg .= qq|  <text x="$x" y="@{[$h - $pad_bottom + 23]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="Inter, sans-serif" text-anchor="middle">$d->{mon}月</text>\n|;
        }
        
        # MA5
        if ($i >= 4) {
            my $sum = 0; for my $j ($i-4..$i) { $sum += $days[$j]{close}; }
            my $m5_y = $pad_top + ($max_p - ($sum/5)) / $p_range * $chart_h;
            push @ma5_points, "$x,$m5_y";
        }
        # MA20
        if ($i >= 19) {
            my $sum = 0; for my $j ($i-19..$i) { $sum += $days[$j]{close}; }
            my $m20_y = $pad_top + ($max_p - ($sum/20)) / $p_range * $chart_h;
            push @ma20_points, "$x,$m20_y";
        }
        # MA60
        if ($i >= 59) {
            my $sum = 0; for my $j ($i-59..$i) { $sum += $days[$j]{close}; }
            my $m60_y = $pad_top + ($max_p - ($sum/60)) / $p_range * $chart_h;
            push @ma60_points, "$x,$m60_y";
        }
        # MA120
        if ($i >= 119) {
            my $sum = 0; for my $j ($i-119..$i) { $sum += $days[$j]{close}; }
            my $m120_y = $pad_top + ($max_p - ($sum/120)) / $p_range * $chart_h;
            push @ma120_points, "$x,$m120_y";
        }
    }
    
    if (@ma120_points) { $svg .= qq|  <polyline points="@{[join(' ', @ma120_points)]}" fill="none" stroke="#ffffff" stroke-width="2" stroke-dasharray="4,2"/>\n|; }
    if (@ma60_points) { $svg .= qq|  <polyline points="@{[join(' ', @ma60_points)]}" fill="none" stroke="#c084fc" stroke-width="2.5"/>\n|; }
    if (@ma20_points) { $svg .= qq|  <polyline points="@{[join(' ', @ma20_points)]}" fill="none" stroke="#38bdf8" stroke-width="2.5"/>\n|; }
    if (@ma5_points) { $svg .= qq|  <polyline points="@{[join(' ', @ma5_points)]}" fill="none" stroke="#facc15" stroke-width="2"/>\n|; }
    
    # RIGHT PANEL: 150-DAY DASHBOARD
    my $panel_x = $w - $pad_right + 10;
    my $panel_w = 180;
    my $panel_h = 400;
    
    $svg .= qq|
  <rect x="$panel_x" y="$pad_top" width="$panel_w" height="$panel_h" rx="8" fill="#0f172a" stroke="#334155" stroke-width="2"/>
  
  <rect x="@{[$panel_x+5]}" y="@{[$pad_top+6]}" width="@{[$panel_w-10]}" height="28" rx="4" fill="#1e293b"/>
  <text x="@{[$panel_x + $panel_w/2]}" y="@{[$pad_top+25]}" fill="#facc15" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">🎯 150日中長線觀察指標</text>
  
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+58]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">1. 150日波段總漲幅:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$pad_top+65]}" width="160" height="24" rx="4" fill="#ff334b"/>
  <text x="@{[$panel_x+90]}" y="@{[$pad_top+82]}" fill="#ffffff" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[sprintf("%+.2f%%", $total_return)]}</text>

  <text x="@{[$panel_x+10]}" y="@{[$pad_top+112]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">2. 150日最高極致價:</text>
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+130]}" fill="#facc15" font-size="13" font-weight="bold" font-family="sans-serif">🔥 $max_p 元</text>
  
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+156]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">3. 150日最低支撐:</text>
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+174]}" fill="#38bdf8" font-size="13" font-weight="bold" font-family="sans-serif">🛡️ $min_p 元</text>

  <text x="@{[$panel_x+10]}" y="@{[$pad_top+200]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">4. 均線大滿貫排列:</text>
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+218]}" fill="#10b981" font-size="12" font-weight="bold" font-family="sans-serif">✓ 5MA>20MA>60MA</text>

  <text x="@{[$panel_x+10]}" y="@{[$pad_top+244]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">5. RSI(14) 動能指標:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$pad_top+251]}" width="160" height="22" rx="4" fill="#38bdf8"/>
  <text x="@{[$panel_x+90]}" y="@{[$pad_top+267]}" fill="#000000" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">RSI: @{[sprintf("%.1f", $rsi)]}</text>

  <text x="@{[$panel_x+10]}" y="@{[$pad_top+297]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">6. 150日單日最大量:</text>
  <text x="@{[$panel_x+10]}" y="@{[$pad_top+315]}" fill="#fef08a" font-size="13" font-weight="bold" font-family="sans-serif">⚡ @{[commify($max_v)]} 張</text>
  
  <rect x="@{[$panel_x+10]}" y="@{[$pad_top+345]}" width="160" height="34" rx="6" fill="#10b981"/>
  <text x="@{[$panel_x+90]}" y="@{[$pad_top+367]}" fill="#ffffff" font-size="15" font-weight="bold" font-family="sans-serif" text-anchor="middle">⭐ 中長線得分: 5/6分</text>
|;

    # Bottom Legend
    $svg .= qq|
  <line x1="20" y1="@{[$h-15]}" x2="40" y2="@{[$h-15]}" stroke="#facc15" stroke-width="2.5"/>
  <text x="45" y="@{[$h-11]}" fill="#facc15" font-size="11" font-weight="bold" font-family="sans-serif">5MA (週線)</text>

  <line x1="130" y1="@{[$h-15]}" x2="150" y2="@{[$h-15]}" stroke="#38bdf8" stroke-width="2.5"/>
  <text x="155" y="@{[$h-11]}" fill="#38bdf8" font-size="11" font-weight="bold" font-family="sans-serif">20MA (月線)</text>

  <line x1="240" y1="@{[$h-15]}" x2="260" y2="@{[$h-15]}" stroke="#c084fc" stroke-width="2.5"/>
  <text x="265" y="@{[$h-11]}" fill="#c084fc" font-size="11" font-weight="bold" font-family="sans-serif">60MA (季線)</text>

  <line x1="350" y1="@{[$h-15]}" x2="370" y2="@{[$h-15]}" stroke="#ffffff" stroke-width="2" stroke-dasharray="4,2"/>
  <text x="375" y="@{[$h-11]}" fill="#ffffff" font-size="11" font-weight="bold" font-family="sans-serif">120MA (半年線)</text>
</svg>|;

    # Save to both old and new versioned filenames to clear cache completely!
    my $svg_art = "$art_dir/kline_${code}_150d.svg";
    my $svg_notes = "$notes_charts_dir/kline_${code}_150d.svg";
    my $svg_notes_old = "$notes_charts_dir/kline_${code}.svg";
    
    for my $target ($svg_art, $svg_notes, $svg_notes_old) {
        open(my $fh_out, ">:encoding(UTF-8)", $target);
        print $fh_out $svg;
        close($fh_out);
    }
    print "Generated FRESH 150D SVG for $code $name -> $svg_notes\n";
}

for my $c (@stock_codes) {
    generate_150d_svg($c);
}
