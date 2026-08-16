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
        # ["115/08/03","1,244,282","1,150,473,080","889.00","940.00","888.00","940.00","+85.00","976",""]
        my $date = $row->[0];
        my $vol = $row->[1]; $vol =~ s/,//g; $vol = int(($vol+0)/1000); # 張
        my $open = $row->[3]; $open =~ s/,//g; $open += 0;
        my $high = $row->[4]; $high =~ s/,//g; $high += 0;
        my $low = $row->[5]; $low =~ s/,//g; $low += 0;
        my $close = $row->[6]; $close =~ s/,//g; $close += 0;
        next if $open <= 0 || $close <= 0;
        
        push @days, {
            date => $date,
            open => $open,
            high => $high,
            low => $low,
            close => $close,
            vol => $vol
        };
    }
    return ($stock_name, \@days);
}

sub generate_real_svg {
    my ($code) = @_;
    my ($name, $days_ref) = fetch_real_kline_data($code);
    unless ($days_ref && @$days_ref) {
        print "Failed to fetch real data for $code\n";
        return;
    }
    
    my @days = @$days_ref;
    my $count = scalar(@days);
    my $latest = $days[-1];
    
    my $w = 640;
    my $h = 380;
    
    # Min/Max price
    my $min_p = 1e9; my $max_p = 0;
    my $max_v = 0;
    for my $d (@days) {
        $min_p = $d->{low} if $d->{low} < $min_p;
        $max_p = $d->{high} if $d->{high} > $max_p;
        $max_v = $d->{vol} if $d->{vol} > $max_v;
    }
    my $p_range = ($max_p - $min_p) || 1;
    $max_v = 1 if $max_v <= 0;
    
    my $chart_h = 220;
    my $vol_h = 60;
    my $pad_top = 45;
    my $pad_left = 60;
    my $cw = ($w - $pad_left - 25) / $count;
    
    my $change_str = sprintf("%+.2f", $latest->{close} - $days[-2]{close}) if $count >= 2;
    $change_str //= "";
    my $change_color = ($latest->{close} >= ($days[-2]{close} || 0)) ? "#ef4444" : "#10b981";
    
    my $svg = qq|<?xml version="1.0" encoding="UTF-8"?>
<svg width="$w" height="$h" xmlns="http://www.w3.org/2000/svg">
  <rect width="100%" height="100%" fill="#0b0f19"/>
  
  <!-- Header -->
  <text x="20" y="28" fill="#f59e0b" font-size="17" font-weight="bold" font-family="Inter, sans-serif">$code $name 真實日K線圖 (2026/08/14)</text>
  <text x="380" y="28" fill="$change_color" font-size="15" font-weight="bold" font-family="Inter, sans-serif">最新收盤: $latest->{close} ($change_str)</text>
  
  <!-- Grid Lines -->
  <line x1="$pad_left" y1="$pad_top" x2="@{[$w-20]}" y2="$pad_top" stroke="#1e293b" stroke-dasharray="3,3"/>
  <line x1="$pad_left" y1="@{[$pad_top + $chart_h/2]}" x2="@{[$w-20]}" y2="@{[$pad_top + $chart_h/2]}" stroke="#1e293b" stroke-dasharray="3,3"/>
  <line x1="$pad_left" y1="@{[$pad_top + $chart_h]}" x2="@{[$w-20]}" y2="@{[$pad_top + $chart_h]}" stroke="#334155"/>
  
  <!-- Price Y-Axis -->
  <text x="10" y="@{[$pad_top + 4]}" fill="#94a3b8" font-size="11" font-family="sans-serif">$max_p</text>
  <text x="10" y="@{[$pad_top + $chart_h/2 + 4]}" fill="#94a3b8" font-size="11" font-family="sans-serif">@{[$min_p + $p_range/2]}</text>
  <text x="10" y="@{[$pad_top + $chart_h]}" fill="#94a3b8" font-size="11" font-family="sans-serif">$min_p</text>
|;

    # Plot Candlesticks & Volume
    my @ma5_points;
    for (my $i = 0; $i < $count; $i++) {
        my $d = $days[$i];
        my $x = $pad_left + $i * $cw + $cw/2;
        my $y_high = $pad_top + ($max_p - $d->{high}) / $p_range * $chart_h;
        my $y_low = $pad_top + ($max_p - $d->{low}) / $p_range * $chart_h;
        my $y_open = $pad_top + ($max_p - $d->{open}) / $p_range * $chart_h;
        my $y_close = $pad_top + ($max_p - $d->{close}) / $p_range * $chart_h;
        
        my $is_up = $d->{close} >= $d->{open};
        my $color = $is_up ? "#ef4444" : "#10b981"; # Red up, Green down (TW stock standard)
        
        my $body_top = $y_open < $y_close ? $y_open : $y_close;
        my $body_h = abs($y_close - $y_open);
        $body_h = 2 if $body_h < 2;
        
        # High/Low Wick
        $svg .= qq|  <line x1="$x" y1="$y_high" x2="$x" y2="$y_low" stroke="$color" stroke-width="1.5"/>\n|;
        # Candlestick Body
        $svg .= qq|  <rect x="@{[$x - $cw*0.35]}" y="$body_top" width="@{[$cw*0.7]}" height="$body_h" fill="$color"/>\n|;
        
        # Volume Bar
        my $v_bar_h = ($d->{vol} / $max_v) * $vol_h;
        $v_bar_h = 2 if $v_bar_h < 2;
        my $v_top = $h - 25 - $v_bar_h;
        $svg .= qq|  <rect x="@{[$x - $cw*0.35]}" y="$v_top" width="@{[$cw*0.7]}" height="$v_bar_h" fill="$color" opacity="0.65"/>\n|;
        
        # MA5
        if ($i >= 4) {
            my $sum = 0;
            for my $j ($i-4..$i) { $sum += $days[$j]{close}; }
            my $ma5 = $sum / 5;
            my $ma5_y = $pad_top + ($max_p - $ma5) / $p_range * $chart_h;
            push @ma5_points, "$x,$ma5_y";
        }
    }
    
    # MA5 Line
    if (@ma5_points) {
        $svg .= qq|  <polyline points="@{[join(' ', @ma5_points)]}" fill="none" stroke="#f59e0b" stroke-width="2"/>\n|;
    }
    
    # Legend
    $svg .= qq|
  <line x1="20" y1="@{[$h-8]}" x2="40" y2="@{[$h-8]}" stroke="#f59e0b" stroke-width="2"/>
  <text x="45" y="@{[$h-5]}" fill="#f59e0b" font-size="11" font-family="sans-serif">5日均線(5MA)</text>
  <text x="180" y="@{[$h-5]}" fill="#94a3b8" font-size="11" font-family="sans-serif">成交量最高: @{[commify($max_v)]} 張</text>
</svg>|;

    my $svg_art = "$art_dir/kline_$code.svg";
    my $svg_notes = "$notes_charts_dir/kline_$code.svg";
    
    for my $target ($svg_art, $svg_notes) {
        open(my $fh_out, ">:encoding(UTF-8)", $target);
        print $fh_out $svg;
        close($fh_out);
    }
    print "Generated REAL SVG for $code $name -> $svg_art\n";
}

for my $c (@stock_codes) {
    generate_real_svg($c);
}
