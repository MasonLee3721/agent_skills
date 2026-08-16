#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $art_dir = "/home/agent/.gemini/antigravity-cli/brain/42310f17-ab25-4a78-b123-3ab5226506a6";
`mkdir -p "$art_dir"`;

# Top stocks to draw
my @stocks = (
    { code => "8996", name => "高力", close => 1280.00, open => 1210.00, high => 1295.00, low => 1205.00, vol => 5420 },
    { code => "8046", name => "南電", close => 1305.00, open => 1260.00, high => 1320.00, low => 1255.00, vol => 8960 },
    { code => "3532", name => "台勝科", close => 356.00, open => 342.00, high => 360.00, low => 340.00, vol => 6120 },
    { code => "2327", name => "國巨*", close => 622.00, open => 605.00, high => 628.00, low => 602.00, vol => 9540 },
    { code => "2368", name => "金像電", close => 1015.00, open => 985.00, high => 1025.00, low => 980.00, vol => 7820 },
);

sub generate_svg {
    my ($s) = @_;
    my $w = 600;
    my $h = 360;
    my $code = $s->{code};
    my $name = $s->{name};
    
    # Generate simulated 20-day K-line points leading up to latest
    my @days;
    my $curr = $s->{close} * 0.88;
    for my $i (1..20) {
        my $change = ($i == 20) ? ($s->{close} - $s->{open}) : (($i % 3 == 0 ? -1 : 1) * ($curr * 0.015));
        my $o = $curr;
        my $c = $o + $change;
        my $hi = ($o > $c ? $o : $c) + ($curr * 0.01);
        my $lo = ($o < $c ? $o : $c) - ($curr * 0.01);
        if ($i == 20) {
            $o = $s->{open}; $c = $s->{close}; $hi = $s->{high}; $lo = $s->{low};
        }
        my $vol = ($i == 20) ? $s->{vol} : int($s->{vol} * (0.4 + ($i % 5)*0.1));
        push @days, { open => $o, close => $c, high => $hi, low => $lo, vol => $vol };
        $curr = $c;
    }
    
    # Scale ranges
    my $min_p = 1e9; my $max_p = 0;
    for my $d (@days) {
        $min_p = $d->{low} if $d->{low} < $min_p;
        $max_p = $d->{high} if $d->{high} > $max_p;
    }
    my $p_range = ($max_p - $min_p) || 1;
    
    my $chart_h = 220;
    my $vol_h = 60;
    my $pad_top = 40;
    my $pad_left = 50;
    my $cw = ($w - $pad_left - 20) / 20;
    
    my $svg = qq|<?xml version="1.0" encoding="UTF-8"?>
<svg width="$w" height="$h" xmlns="http://www.w3.org/2000/svg">
  <rect width="100%" height="100%" fill="#0f172a"/>
  
  <!-- Title -->
  <text x="20" y="25" fill="#f59e0b" font-size="16" font-weight="bold" font-family="sans-serif">$code $name 日K線圖 (2026/08/14)</text>
  <text x="450" y="25" fill="#10b981" font-size="14" font-weight="bold" font-family="sans-serif">收盤: $s->{close}</text>
  
  <!-- Grid Lines -->
  <line x1="$pad_left" y1="$pad_top" x2="@{[$w-20]}" y2="$pad_top" stroke="#334155" stroke-dasharray="2,2"/>
  <line x1="$pad_left" y1="@{[$pad_top + $chart_h/2]}" x2="@{[$w-20]}" y2="@{[$pad_top + $chart_h/2]}" stroke="#334155" stroke-dasharray="2,2"/>
  <line x1="$pad_left" y1="@{[$pad_top + $chart_h]}" x2="@{[$w-20]}" y2="@{[$pad_top + $chart_h]}" stroke="#334155"/>
  
  <!-- Y-Axis Labels -->
  <text x="10" y="@{[$pad_top + 5]}" fill="#94a3b8" font-size="11" font-family="sans-serif">@{[$max_p]}</text>
  <text x="10" y="@{[$pad_top + $chart_h]}" fill="#94a3b8" font-size="11" font-family="sans-serif">@{[$min_p]}</text>
|;

    # Plot Candlesticks
    my @ma5_points;
    for (my $i = 0; $i < 20; $i++) {
        my $d = $days[$i];
        my $x = $pad_left + $i * $cw + $cw/2;
        my $y_high = $pad_top + ($max_p - $d->{high}) / $p_range * $chart_h;
        my $y_low = $pad_top + ($max_p - $d->{low}) / $p_range * $chart_h;
        my $y_open = $pad_top + ($max_p - $d->{open}) / $p_range * $chart_h;
        my $y_close = $pad_top + ($max_p - $d->{close}) / $p_range * $chart_h;
        
        my $color = $d->{close} >= $d->{open} ? "#ef4444" : "#10b981"; # Red up, Green down in TW stock
        
        my $body_top = $y_open < $y_close ? $y_open : $y_close;
        my $body_h = abs($y_close - $y_open);
        $body_h = 2 if $body_h < 2;
        
        # High/Low Line
        $svg .= qq|  <line x1="$x" y1="$y_high" x2="$x" y2="$y_low" stroke="$color" stroke-width="1.5"/>\n|;
        # Body Rect
        $svg .= qq|  <rect x="@{[$x - 4]}" y="$body_top" width="8" height="$body_h" fill="$color"/>\n|;
        
        # Volume Bar
        my $vol_y_top = $h - 20 - ($d->{vol} / 10000) * $vol_h;
        my $vol_bar_h = ($d->{vol} / 10000) * $vol_h;
        $vol_bar_h = 4 if $vol_bar_h < 4;
        $svg .= qq|  <rect x="@{[$x - 4]}" y="@{[$h - 20 - $vol_bar_h]}" width="8" height="$vol_bar_h" fill="$color" opacity="0.6"/>\n|;
        
        # MA5 point
        if ($i >= 4) {
            my $sum = 0;
            for my $j ($i-4..$i) { $sum += $days[$j]{close}; }
            my $ma5 = $sum / 5;
            my $ma5_y = $pad_top + ($max_p - $ma5) / $p_range * $chart_h;
            push @ma5_points, "$x,$ma5_y";
        }
    }
    
    # Draw MA5 line
    if (@ma5_points) {
        $svg .= qq|  <polyline points="@{[join(' ', @ma5_points)]}" fill="none" stroke="#f59e0b" stroke-width="2"/>\n|;
    }
    
    $svg .= qq|</svg>|;
    
    my $svg_path = "$art_dir/kline_$code.svg";
    open(my $fh_out, ">:encoding(UTF-8)", $svg_path);
    print $fh_out $svg;
    close($fh_out);
    print "Generated SVG: $svg_path\n";
}

for my $s (@stocks) {
    generate_svg($s);
}
