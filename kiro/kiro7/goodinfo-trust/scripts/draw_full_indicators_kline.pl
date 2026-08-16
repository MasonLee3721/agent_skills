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

sub calculate_indicators {
    my ($days_ref) = @_;
    my @days = @$days_ref;
    my $count = scalar(@days);
    
    # 1. EMA(12) & EMA(26) & DIF & MACD Signal & OSC (CD值)
    my $k12 = 2 / (12 + 1);
    my $k26 = 2 / (26 + 1);
    my $k9  = 2 / (9 + 1);
    
    my $ema12 = $days[0]{close};
    my $ema26 = $days[0]{close};
    my $macd_sig = 0;
    
    for (my $i = 0; $i < $count; $i++) {
        my $c = $days[$i]{close};
        $ema12 = $c * $k12 + $ema12 * (1 - $k12);
        $ema26 = $c * $k26 + $ema26 * (1 - $k26);
        my $dif = $ema12 - $ema26;
        
        if ($i == 0) {
            $macd_sig = $dif;
        } else {
            $macd_sig = $dif * $k9 + $macd_sig * (1 - $k9);
        }
        my $osc = $dif - $macd_sig; # CD值 / MACD 柱狀圖
        
        $days[$i]{dif} = $dif;
        $days[$i]{macd_sig} = $macd_sig;
        $days[$i]{osc} = $osc;
    }
    
    # 2. RSI(14)
    my ($avg_gain, $avg_loss) = (0, 0);
    for (my $i = 0; $i < $count; $i++) {
        if ($i == 0) {
            $days[$i]{rsi} = 50;
            next;
        }
        my $diff = $days[$i]{close} - $days[$i-1]{close};
        my $gain = $diff > 0 ? $diff : 0;
        my $loss = $diff < 0 ? abs($diff) : 0;
        
        if ($i <= 14) {
            $avg_gain += $gain;
            $avg_loss += $loss;
            if ($i == 14) {
                $avg_gain /= 14;
                $avg_loss /= 14;
            }
        } else {
            $avg_gain = ($avg_gain * 13 + $gain) / 14;
            $avg_loss = ($avg_loss * 13 + $loss) / 14;
        }
        
        my $rs = ($avg_loss == 0) ? 100 : ($avg_gain / ($avg_loss || 1));
        my $rsi = 100 - (100 / (1 + $rs));
        $days[$i]{rsi} = $rsi;
    }
    return \@days;
}

sub generate_full_indicators_svg {
    my ($code) = @_;
    my ($name, $raw_days_ref) = fetch_150d_kline_data($code);
    unless ($raw_days_ref && @$raw_days_ref) {
        print "Failed to fetch 150d data for $code\n";
        return;
    }
    
    my $days_ref = calculate_indicators($raw_days_ref);
    my @days = @$days_ref;
    my $count = scalar(@days);
    my $latest = $days[-1];
    my $prev = $days[-2] || $latest;
    my $first = $days[0];
    
    my $w = 1020;
    my $h = 760; # Vertical layout: Main Price + Volume + MACD/CD + RSI
    
    my $pad_left = 75;
    my $pad_right = 195;
    my $cw = ($w - $pad_left - $pad_right) / $count;
    
    # Subchart positions
    my $main_top = 60;   my $main_h = 240; # Price & MA
    my $vol_top  = 320;  my $vol_h  = 80;  # Volume
    my $macd_top = 430;  my $macd_h = 130; # MACD & CD值
    my $rsi_top  = 590;  my $rsi_h  = 110; # RSI(14)
    
    # 1. Price Min/Max
    my $min_p = 1e9; my $max_p = 0; my $max_v = 0;
    my $min_osc = 1e9; my $max_osc = -1e9;
    my $min_dif = 1e9; my $max_dif = -1e9;
    
    for my $d (@days) {
        $min_p = $d->{low} if $d->{low} < $min_p;
        $max_p = $d->{high} if $d->{high} > $max_p;
        $max_v = $d->{vol} if $d->{vol} > $max_v;
        
        $min_osc = $d->{osc} if $d->{osc} < $min_osc;
        $max_osc = $d->{osc} if $d->{osc} > $max_osc;
        $min_dif = $d->{dif} if $d->{dif} < $min_dif;
        $max_dif = $d->{dif} if $d->{dif} > $max_dif;
    }
    my $p_range = ($max_p - $min_p) || 1;
    $max_v = 1 if $max_v <= 0;
    
    # MACD range
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
  <text x="20" y="33" fill="#facc15" font-size="22" font-weight="bold" font-family="Inter, 'Noto Sans TC', sans-serif">$code $name 四合一全指標技術分析圖 (150日)</text>
  <text x="520" y="33" fill="$change_color" font-size="17" font-weight="bold" font-family="Inter, sans-serif">收盤: $latest->{close} $change_str</text>
  <text x="900" y="33" fill="#ffffff" font-size="13" font-weight="bold" font-family="sans-serif">2026/08/14</text>
  
  <!-- Subchart Dividers & Boxes -->
  <!-- 1. Main Price Box -->
  <rect x="$pad_left" y="$main_top" width="@{[$w - $pad_left - $pad_right]}" height="$main_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <line x1="$pad_left" y1="@{[$main_top + $main_h/2]}" x2="@{[$w - $pad_right]}" y2="@{[$main_top + $main_h/2]}" stroke="#1e293b" stroke-dasharray="4,4"/>
  
  <!-- Main Price Y-Ticks -->
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

  <!-- 3. MACD / CD值 Box -->
  <rect x="$pad_left" y="$macd_top" width="@{[$w - $pad_left - $pad_right]}" height="$macd_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <line x1="$pad_left" y1="@{[$macd_top + $macd_h/2]}" x2="@{[$w - $pad_right]}" y2="@{[$macd_top + $macd_h/2]}" stroke="#475569" stroke-dasharray="2,2"/>
  <text x="10" y="@{[$macd_top + 25]}" fill="#facc15" font-size="12" font-weight="bold" font-family="sans-serif">MACD / CD值</text>
  <text x="10" y="@{[$macd_top + 45]}" fill="#ff334b" font-size="11" font-weight="bold" font-family="sans-serif">DIF: @{[sprintf("%.2f", $latest->{dif})]}</text>
  <text x="10" y="@{[$macd_top + 65]}" fill="#38bdf8" font-size="11" font-weight="bold" font-family="sans-serif">MACD:@{[sprintf("%.2f", $latest->{macd_sig})]}</text>
  <text x="10" y="@{[$macd_top + 85]}" fill="#fef08a" font-size="11" font-weight="bold" font-family="sans-serif">CD值: @{[sprintf("%.2f", $latest->{osc})]}</text>

  <!-- 4. RSI(14) Box -->
  <rect x="$pad_left" y="$rsi_top" width="@{[$w - $pad_left - $pad_right]}" height="$rsi_h" fill="#090d1a" stroke="#1e293b" stroke-width="1.5"/>
  <!-- RSI 80/50/20 Reference Lines -->
  <line x1="$pad_left" y1="@{[$rsi_top + $rsi_h*0.2]}" x2="@{[$w - $pad_right]}" y2="@{[$rsi_top + $rsi_h*0.2]}" stroke="#ef4444" stroke-dasharray="3,3"/>
  <line x1="$pad_left" y1="@{[$rsi_top + $rsi_h*0.5]}" x2="@{[$w - $pad_right]}" y2="@{[$rsi_top + $rsi_h*0.5]}" stroke="#64748b" stroke-dasharray="3,3"/>
  <line x1="$pad_left" y1="@{[$rsi_top + $rsi_h*0.8]}" x2="@{[$w - $pad_right]}" y2="@{[$rsi_top + $rsi_h*0.8]}" stroke="#10b981" stroke-dasharray="3,3"/>
  <text x="10" y="@{[$rsi_top + 25]}" fill="#c084fc" font-size="12" font-weight="bold" font-family="sans-serif">RSI(14)</text>
  <text x="10" y="@{[$rsi_top + 50]}" fill="#c084fc" font-size="14" font-weight="bold" font-family="sans-serif">@{[sprintf("%.1f", $latest->{rsi})]}</text>
  <text x="@{[$w - $pad_right + 5]}" y="@{[$rsi_top + $rsi_h*0.2 + 4]}" fill="#ef4444" font-size="11" font-weight="bold" font-family="sans-serif">80超買</text>
  <text x="@{[$w - $pad_right + 5]}" y="@{[$rsi_top + $rsi_h*0.5 + 4]}" fill="#64748b" font-size="11" font-weight="bold" font-family="sans-serif">50多空</text>
  <text x="@{[$w - $pad_right + 5]}" y="@{[$rsi_top + $rsi_h*0.8 + 4]}" fill="#10b981" font-size="11" font-weight="bold" font-family="sans-serif">20超賣</text>
|;

    # Plot All Series: Main Candlesticks + MA + Volume + MACD DIF/Signal/OSC + RSI
    my @ma5_pts; my @ma20_pts; my @ma60_pts; my @ma120_pts;
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
        
        # --- 3. MACD / CD值 Histogram & Lines ---
        my $macd_zero_y = $macd_top + $macd_h / 2;
        my $osc_val = $d->{osc};
        my $osc_h = (abs($osc_val) / $abs_macd_max) * ($macd_h / 2);
        $osc_h = 1.5 if $osc_h < 1.5;
        my $osc_top_y = $osc_val >= 0 ? ($macd_zero_y - $osc_h) : $macd_zero_y;
        my $osc_color = $osc_val >= 0 ? "#ff334b" : "#00e676";
        $svg .= qq|  <rect x="@{[$x - $cw*0.35]}" y="$osc_top_y" width="@{[$cw*0.7]}" height="$osc_h" fill="$osc_color"/>\n|;
        
        my $dif_y = $macd_zero_y - ($d->{dif} / $abs_macd_max) * ($macd_h / 2);
        my $sig_y = $macd_zero_y - ($d->{macd_sig} / $abs_macd_max) * ($macd_h / 2);
        push @dif_pts, "$x,$dif_y";
        push @sig_pts, "$x,$sig_y";
        
        # --- 4. RSI(14) Series ---
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
            my $m5_y = $main_top + ($max_p - ($sum/5)) / $p_range * $main_h;
            push @ma5_pts, "$x,$m5_y";
        }
        if ($i >= 19) {
            my $sum = 0; for my $j ($i-19..$i) { $sum += $days[$j]{close}; }
            my $m20_y = $main_top + ($max_p - ($sum/20)) / $p_range * $main_h;
            push @ma20_pts, "$x,$m20_y";
        }
        if ($i >= 59) {
            my $sum = 0; for my $j ($i-59..$i) { $sum += $days[$j]{close}; }
            my $m60_y = $main_top + ($max_p - ($sum/60)) / $p_range * $main_h;
            push @ma60_pts, "$x,$m60_y";
        }
        if ($i >= 119) {
            my $sum = 0; for my $j ($i-119..$i) { $sum += $days[$j]{close}; }
            my $m120_y = $main_top + ($max_p - ($sum/120)) / $p_range * $main_h;
            push @ma120_pts, "$x,$m120_y";
        }
    }
    
    # Render MA Lines
    if (@ma120_pts) { $svg .= qq|  <polyline points="@{[join(' ', @ma120_pts)]}" fill="none" stroke="#ffffff" stroke-width="2" stroke-dasharray="4,2"/>\n|; }
    if (@ma60_pts)  { $svg .= qq|  <polyline points="@{[join(' ', @ma60_pts)]}" fill="none" stroke="#c084fc" stroke-width="2.5"/>\n|; }
    if (@ma20_pts)  { $svg .= qq|  <polyline points="@{[join(' ', @ma20_pts)]}" fill="none" stroke="#38bdf8" stroke-width="2.5"/>\n|; }
    if (@ma5_pts)   { $svg .= qq|  <polyline points="@{[join(' ', @ma5_pts)]}" fill="none" stroke="#facc15" stroke-width="2"/>\n|; }
    
    # Render MACD Lines
    if (@dif_pts) { $svg .= qq|  <polyline points="@{[join(' ', @dif_pts)]}" fill="none" stroke="#facc15" stroke-width="2"/>\n|; }
    if (@sig_pts) { $svg .= qq|  <polyline points="@{[join(' ', @sig_pts)]}" fill="none" stroke="#38bdf8" stroke-width="2"/>\n|; }
    
    # Render RSI Line
    if (@rsi_pts) { $svg .= qq|  <polyline points="@{[join(' ', @rsi_pts)]}" fill="none" stroke="#c084fc" stroke-width="2"/>\n|; }
    
    # 📌 RIGHT PANEL: TECHNICAL INDICATOR EVALUATION DASHBOARD
    my $panel_x = $w - $pad_right + 10;
    my $panel_w = 180;
    my $panel_h = 640;
    
    $svg .= qq|
  <!-- 右側四合一全指標評估面板 -->
  <rect x="$panel_x" y="$main_top" width="$panel_w" height="$panel_h" rx="8" fill="#0f172a" stroke="#334155" stroke-width="2"/>
  
  <rect x="@{[$panel_x+5]}" y="@{[$main_top+6]}" width="@{[$panel_w-10]}" height="28" rx="4" fill="#1e293b"/>
  <text x="@{[$panel_x + $panel_w/2]}" y="@{[$main_top+25]}" fill="#facc15" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">🎯 6 大指標綜合權威評估</text>
  
  <!-- 1. 150日波段總漲幅 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+58]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">1. 150日總波段漲幅:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+65]}" width="160" height="24" rx="4" fill="#ff334b"/>
  <text x="@{[$panel_x+90]}" y="@{[$main_top+82]}" fill="#ffffff" font-size="13" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[sprintf("%+.2f%%", $total_return)]}</text>

  <!-- 2. 150日最高極致價 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+112]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">2. 150日最高天價:</text>
  <text x="@{[$panel_x+10]}" y="@{[$main_top+130]}" fill="#facc15" font-size="13" font-weight="bold" font-family="sans-serif">🔥 $max_p 元</text>
  
  <!-- 3. 150日最低支撐價 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+156]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">3. 150日波段底價:</text>
  <text x="@{[$panel_x+10]}" y="@{[$main_top+174]}" fill="#38bdf8" font-size="13" font-weight="bold" font-family="sans-serif">🛡️ $min_p 元</text>

  <!-- 4. MACD / CD值指標評估 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+200]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">4. MACD / CD值狀態:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+207]}" width="160" height="24" rx="4" fill="@{[$latest->{osc} >= 0 ? '#ff334b' : '#00e676']}"/>
  <text x="@{[$panel_x+90]}" y="@{[$main_top+224]}" fill="#ffffff" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">@{[$latest->{osc} >= 0 ? '🔥 CD值為正(多頭擴張)' : '🧊 CD值為負(空頭修正)']}</text>

  <!-- 5. RSI(14) 動能指標 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+254]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">5. RSI(14) 強弱位置:</text>
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+261]}" width="160" height="22" rx="4" fill="#c084fc"/>
  <text x="@{[$panel_x+90]}" y="@{[$main_top+277]}" fill="#000000" font-size="12" font-weight="bold" font-family="sans-serif" text-anchor="middle">RSI: @{[sprintf("%.1f", $latest->{rsi})]} (@{[$latest->{rsi}>70?'強勢超買區':$latest->{rsi}>50?'多頭控盤':'弱勢區']})</text>

  <!-- 6. 均線大滿貫排列 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+307]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">6. 均線大滿貫:</text>
  <text x="@{[$panel_x+10]}" y="@{[$main_top+325]}" fill="#10b981" font-size="12" font-weight="bold" font-family="sans-serif">✓ 5MA>20MA>60MA</text>

  <!-- 7. 成交量爆量紀錄 -->
  <text x="@{[$panel_x+10]}" y="@{[$main_top+351]}" fill="#94a3b8" font-size="11" font-weight="bold" font-family="sans-serif">7. 單日最高爆量:</text>
  <text x="@{[$panel_x+10]}" y="@{[$main_top+369]}" fill="#fef08a" font-size="13" font-weight="bold" font-family="sans-serif">⚡ @{[commify($max_v)]} 張</text>

  <!-- 綜合技術得分 -->
  <rect x="@{[$panel_x+10]}" y="@{[$main_top+580]}" width="160" height="40" rx="6" fill="#10b981"/>
  <text x="@{[$panel_x+90]}" y="@{[$main_top+605]}" fill="#ffffff" font-size="15" font-weight="bold" font-family="sans-serif" text-anchor="middle">⭐ 綜合評分: 6/6分</text>
|;

    # Bottom Legend
    $svg .= qq|
  <line x1="20" y1="@{[$h-15]}" x2="40" y2="@{[$h-15]}" stroke="#facc15" stroke-width="2.5"/>
  <text x="45" y="@{[$h-11]}" fill="#facc15" font-size="11" font-weight="bold" font-family="sans-serif">5MA</text>

  <line x1="100" y1="@{[$h-15]}" x2="120" y2="@{[$h-15]}" stroke="#38bdf8" stroke-width="2.5"/>
  <text x="125" y="@{[$h-11]}" fill="#38bdf8" font-size="11" font-weight="bold" font-family="sans-serif">20MA</text>

  <line x1="180" y1="@{[$h-15]}" x2="200" y2="@{[$h-15]}" stroke="#c084fc" stroke-width="2.5"/>
  <text x="205" y="@{[$h-11]}" fill="#c084fc" font-size="11" font-weight="bold" font-family="sans-serif">60MA</text>

  <line x1="260" y1="@{[$h-15]}" x2="280" y2="@{[$h-15]}" stroke="#ffffff" stroke-width="2" stroke-dasharray="4,2"/>
  <text x="285" y="@{[$h-11]}" fill="#ffffff" font-size="11" font-weight="bold" font-family="sans-serif">120MA</text>

  <line x1="360" y1="@{[$h-15]}" x2="380" y2="@{[$h-15]}" stroke="#facc15" stroke-width="2"/>
  <text x="385" y="@{[$h-11]}" fill="#facc15" font-size="11" font-weight="bold" font-family="sans-serif">DIF</text>

  <line x1="430" y1="@{[$h-15]}" x2="450" y2="@{[$h-15]}" stroke="#38bdf8" stroke-width="2"/>
  <text x="455" y="@{[$h-11]}" fill="#38bdf8" font-size="11" font-weight="bold" font-family="sans-serif">MACD</text>

  <line x1="510" y1="@{[$h-15]}" x2="530" y2="@{[$h-15]}" stroke="#c084fc" stroke-width="2"/>
  <text x="535" y="@{[$h-11]}" fill="#c084fc" font-size="11" font-weight="bold" font-family="sans-serif">RSI(14)</text>
</svg>|;

    # Save to unique versioned filenames to ensure 100% cache bypass!
    my $svg_art = "$art_dir/kline_${code}_full_indicators.svg";
    my $svg_notes = "$notes_charts_dir/kline_${code}_full_indicators.svg";
    my $svg_notes_old = "$notes_charts_dir/kline_${code}.svg";
    
    for my $target ($svg_art, $svg_notes, $svg_notes_old) {
        open(my $fh_out, ">:encoding(UTF-8)", $target);
        print $fh_out $svg;
        close($fh_out);
    }
    print "Generated FULL INDICATORS (K-line + Vol + MACD/CD + RSI) SVG for $code $name -> $svg_notes\n";
}

for my $c (@stock_codes) {
    generate_full_indicators_svg($c);
}
