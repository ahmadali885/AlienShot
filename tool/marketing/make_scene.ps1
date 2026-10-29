param([string]$Root = (Resolve-Path "$PSScriptRoot\..\..").Path)
# Renders tool/marketing/scene.png: a made-up analytics dashboard (1440x900
# logical at 2x) that the product-shot test "takes a screenshot" of.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

function Load-Family($file) {
  $pfc = New-Object System.Drawing.Text.PrivateFontCollection
  $pfc.AddFontFile($file)
  $script:collections += ,$pfc
  return $pfc.Families[0]
}
$script:collections = @()
$med = Load-Family "$Root\assets\fonts\Urbanist-Medium.ttf"
$semi = Load-Family "$Root\assets\fonts\Urbanist-SemiBold.ttf"
$bold = Load-Family "$Root\assets\fonts\Urbanist-Bold.ttf"
$display = Load-Family "$Root\assets\fonts\Outfit-Bold.ttf"

function C($hex, $a = 255) {
  $h = $hex.TrimStart('#')
  [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16))
}
function Brush($hex, $a = 255) { New-Object System.Drawing.SolidBrush (C $hex $a) }
function Font($family, $px) { New-Object System.Drawing.Font $family, $px, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel) }
function Text($g, $s, $font, $hex, $x, $y) { $g.DrawString($s, $font, (Brush $hex), [single]$x, [single]$y, [System.Drawing.StringFormat]::GenericTypographic) }
function RoundRect($x, $y, $w, $h, $r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = [math]::Min($r * 2, [math]::Min($w, $h))
  $p.AddArc([single]$x, [single]$y, [single]$d, [single]$d, 180, 90)
  $p.AddArc([single]($x + $w - $d), [single]$y, [single]$d, [single]$d, 270, 90)
  $p.AddArc([single]($x + $w - $d), [single]($y + $h - $d), [single]$d, [single]$d, 0, 90)
  $p.AddArc([single]$x, [single]($y + $h - $d), [single]$d, [single]$d, 90, 90)
  $p.CloseFigure()
  return $p
}
function Card($g, $x, $y, $w, $h) {
  $g.FillPath((Brush '#0B2A33' 10), (RoundRect $x ($y + 2) $w $h 14))
  $g.FillPath((Brush '#FFFFFF'), (RoundRect $x $y $w $h 14))
  $g.DrawPath((New-Object System.Drawing.Pen (C '#E3EAEE'), 1), (RoundRect $x $y $w $h 14))
}

$bmp = New-Object System.Drawing.Bitmap 2880, 1800
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
$g.ScaleTransform(2, 2)
$g.Clear((C '#F3F6F8'))

# Sidebar.
$g.FillRectangle((Brush '#FFFFFF'), 0, 0, 230, 900)
$g.FillRectangle((Brush '#E3EAEE'), 230, 0, 1, 900)
$g.FillPath((Brush '#2E8BFF'), (RoundRect 24 26 30 30 9))
Text $g 'N' (Font $display 18) '#FFFFFF' 32.5 30
Text $g 'Nimbus' (Font $display 21) '#0E1E25' 64 29
$nav = 'Dashboard', 'Sales', 'Customers', 'Products', 'Reports', 'Settings'
for ($i = 0; $i -lt $nav.Count; $i++) {
  $y = 96 + $i * 44
  if ($i -eq 0) { $g.FillPath((Brush '#2E8BFF' 26), (RoundRect 14 ($y - 9) 202 36 10)) }
  $hex = if ($i -eq 0) { '#2E8BFF' } else { '#5B6B73' }
  $g.FillPath((Brush $hex 200), (RoundRect 28 ($y + 1) 16 16 4))
  Text $g $nav[$i] (Font $semi 15) $hex 56 ($y - 1)
}

# Header.
Text $g 'Sales overview' (Font $display 28) '#0E1E25' 262 30
Text $g 'Here is how your store did this year.' (Font $med 15) '#6B7C84' 263 70
$g.FillPath((Brush '#FFFFFF'), (RoundRect 1150 34 150 38 19))
$g.DrawPath((New-Object System.Drawing.Pen (C '#E3EAEE'), 1), (RoundRect 1150 34 150 38 19))
Text $g 'Jan - Dec 2026' (Font $semi 14) '#33444C' 1172 44
$g.FillEllipse((Brush '#FFB454'), 1322, 32, 42, 42)
Text $g 'AK' (Font $bold 15) '#FFFFFF' 1332 44

# KPI cards.
$kpis = @(@('Revenue', '$48.2k', '+12.4%'), @('Orders', '1,284', '+8.1%'), @('Visitors', '32.9k', '+4.6%'), @('Conversion', '3.9%', '+0.7%'))
for ($i = 0; $i -lt 4; $i++) {
  $x = 262 + $i * 284
  Card $g $x 110 266 112
  Text $g $kpis[$i][0] (Font $semi 14) '#6B7C84' ($x + 20) 128
  Text $g $kpis[$i][1] (Font $display 30) '#0E1E25' ($x + 20) 154
  $g.FillPath((Brush '#21B26F' 30), (RoundRect ($x + 172) 162 72 26 13))
  Text $g $kpis[$i][2] (Font $bold 13) '#169A5C' ($x + 182) 167
}

# Monthly revenue chart.
Card $g 262 242 760 400
Text $g 'Monthly revenue' (Font $display 19) '#0E1E25' 284 262
Text $g 'Thousands of dollars' (Font $med 13) '#6B7C84' 285 290
$months = 'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
$values = 22, 28, 25, 34, 31, 38, 36, 44, 40, 58, 47, 51
$base = 600; $scale = 4.4
for ($k = 0; $k -le 4; $k++) {
  $y = $base - $k * 15 * $scale
  $g.FillRectangle((Brush '#E8EEF1'), 320, [single]$y, 680, 1)
  Text $g ("{0}" -f ($k * 15)) (Font $med 12) '#93A3AA' 286 ($y - 8)
}
for ($i = 0; $i -lt 12; $i++) {
  $x = 334 + $i * 56; $h = $values[$i] * $scale
  $hex = if ($i -eq 9) { '#2E8BFF' } else { '#A9C8F0' }
  $g.FillPath((Brush $hex), (RoundRect $x ($base - $h) 30 $h 6))
  Text $g $months[$i] (Font $semi 12) '#6B7C84' ($x + 2) 610
}

# Traffic sources donut.
Card $g 1042 242 374 400
Text $g 'Traffic sources' (Font $display 19) '#0E1E25' 1064 262
$slices = @(@(46, '#2E8BFF', 'Search'), @(27, '#21B26F', 'Social'), @(17, '#FFB454', 'Email'), @(10, '#B57CFF', 'Direct'))
$start = -90
foreach ($s in $slices) {
  $sweep = $s[0] * 3.6
  $pen = New-Object System.Drawing.Pen (C $s[1]), 30
  $g.DrawArc($pen, 1149, 310, 160, 160, [single]($start + 1), [single]($sweep - 2))
  $start += $sweep
}
Text $g '32.9k' (Font $display 24) '#0E1E25' 1197 372
Text $g 'visitors' (Font $med 13) '#6B7C84' 1206 402
for ($i = 0; $i -lt 4; $i++) {
  $y = 516 + $i * 28
  $g.FillEllipse((Brush $slices[$i][1]), 1072, [single]($y + 3), 11, 11)
  Text $g $slices[$i][2] (Font $semi 14) '#33444C' 1094 $y
  Text $g ("{0}%" -f $slices[$i][0]) (Font $bold 14) '#0E1E25' 1360 $y
}

# Recent orders.
Card $g 262 662 1154 220
Text $g 'Recent orders' (Font $display 19) '#0E1E25' 284 680
$rows = @(@('#1042', 'Sara Malik', 'Wireless earbuds', '$129.00', 'Paid'), @('#1041', 'Omar Khan', 'Smart watch', '$249.00', 'Paid'), @('#1040', 'Lena Park', 'Laptop stand', '$59.00', 'Pending'), @('#1039', 'Ravi Shah', 'USB-C hub', '$39.00', 'Paid'))
$cols = 284, 380, 560, 900, 1060
Text $g 'ORDER' (Font $bold 11) '#93A3AA' 284 716
Text $g 'CUSTOMER' (Font $bold 11) '#93A3AA' 380 716
Text $g 'PRODUCT' (Font $bold 11) '#93A3AA' 560 716
Text $g 'AMOUNT' (Font $bold 11) '#93A3AA' 900 716
Text $g 'STATUS' (Font $bold 11) '#93A3AA' 1060 716
for ($r = 0; $r -lt 4; $r++) {
  $y = 742 + $r * 34
  $g.FillRectangle((Brush '#EEF2F4'), 284, [single]($y - 8), 1110, 1)
  for ($c = 0; $c -lt 4; $c++) { Text $g $rows[$r][$c] (Font $semi 14) '#33444C' $cols[$c] $y }
  $paid = $rows[$r][4] -eq 'Paid'
  $g.FillPath((Brush ($(if ($paid) { '#21B26F' } else { '#FFB454' })) 34), (RoundRect 1056 ($y - 4) 70 24 12))
  Text $g $rows[$r][4] (Font $bold 12) ($(if ($paid) { '#169A5C' } else { '#C77D12' })) 1068 ($y)
}

$g.Dispose()
$bmp.Save("$PSScriptRoot\scene.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"$PSScriptRoot\scene.png"
