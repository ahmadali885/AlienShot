param([string]$Root = (Resolve-Path "$PSScriptRoot\..\..").Path, [string]$Out = "$((Resolve-Path "$PSScriptRoot\..\..").Path)\marketing")
# Renders AlienShot's advertising pack into marketing/:
#   logo/  — the app icon, horizontal logos for dark and light backgrounds,
#            and the white alien mark, all transparent PNGs;
#   banner-1200x628.png (Facebook / web), banner-1080x1080.png (Instagram
#   post), banner-1080x1920.png (story / WhatsApp status).
# Same look as the DMG window: the hero.frag marble as a night sky, Outfit
# wordmark, Urbanist copy. Run on Windows PowerShell.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// CPU port of shaders/hero.frag (dark branch), frozen at one moment.
public static class AdMarble {
  static double Fract(double x) { return x - Math.Floor(x); }
  static void Hash(double px, double py, out double hx, out double hy) {
    hx = -1 + 2 * Fract(Math.Sin(px * 127.1 + py * 311.7) * 43758.5453123);
    hy = -1 + 2 * Fract(Math.Sin(px * 269.5 + py * 183.3) * 43758.5453123);
  }
  static double Noise(double x, double y) {
    double ix = Math.Floor(x), iy = Math.Floor(y), fx = x - ix, fy = y - iy;
    double ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
    double ax, ay, bx, by, cx, cy, dx, dy;
    Hash(ix, iy, out ax, out ay); Hash(ix + 1, iy, out bx, out by);
    Hash(ix, iy + 1, out cx, out cy); Hash(ix + 1, iy + 1, out dx, out dy);
    double d0 = ax * fx + ay * fy, d1 = bx * (fx - 1) + by * fy;
    double d2 = cx * fx + cy * (fy - 1), d3 = dx * (fx - 1) + dy * (fy - 1);
    double a = d0 + (d1 - d0) * ux, b = d2 + (d3 - d2) * ux;
    return a + (b - a) * uy;
  }
  static double Fbm(double x, double y) {
    double v = 0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * Noise(x, y); x *= 2; y *= 2; a *= 0.5; }
    return v;
  }
  static double Smooth(double e0, double e1, double x) {
    double t = Math.Max(0, Math.Min(1, (x - e0) / (e1 - e0)));
    return t * t * (3 - 2 * t);
  }
  static double Mix(double a, double b, double t) { return a + (b - a) * t; }

  // `scale` is the pattern's size in pixels per unit, so every banner shows
  // marble of the same grain whatever its shape.
  public static Bitmap Render(int w, int h, double time, double scale) {
    var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    var px = new byte[data.Stride * h];
    double t = time * 0.045;
    for (int j = 0; j < h; j++) {
      for (int i = 0; i < w; i++) {
        double x = (i + 0.5) / scale, y = (h - (j + 0.5)) / scale;
        double qx = Fbm(x + t, y + t), qy = Fbm(x + 5.2 - t, y + 1.3 - t);
        double rx = Fbm(x + 2 * qx + 1.7, y + 2 * qy + 9.2);
        double ry = Fbm(x + 2 * qx + 8.3 - t, y + 2 * qy + 2.8 - t);
        double f = Fbm(x + 2 * rx, y + 2 * ry);

        double s1 = Smooth(-0.25, 0.6, f), s2 = Smooth(0.15, 0.95, rx);
        double s3 = Math.Pow(Smooth(0.5, 1.0, f + ry * 0.35), 1.7) * 0.8;
        double cr = Mix(Mix(Mix(0.016, 0.0, s1), 0.0, s2), 0.122, s3);
        double cg = Mix(Mix(Mix(0.078, 0.282, s1), 0.372, s2), 0.592, s3);
        double cb = Mix(Mix(Mix(0.094, 0.345, s1), 0.454, s2), 0.690, s3);

        double u = (i + 0.5) / w, v = (j + 0.5) / h;
        double lx = u - 0.6, ly = v - 0.5;
        double vig = Smooth(1.2, 0.1, Math.Sqrt(lx * lx + ly * ly));
        double k = 0.74 + 0.55 * vig;
        int o = j * data.Stride + i * 4;
        px[o] = (byte)Math.Min(255, cb * k * 255);
        px[o + 1] = (byte)Math.Min(255, cg * k * 255);
        px[o + 2] = (byte)Math.Min(255, cr * k * 255);
        px[o + 3] = 255;
      }
    }
    Marshal.Copy(px, 0, data.Scan0, px.Length);
    bmp.UnlockBits(data);
    return bmp;
  }
}
"@

function Load-Family($file) {
  $pfc = New-Object System.Drawing.Text.PrivateFontCollection
  $pfc.AddFontFile($file)
  $script:collections += ,$pfc
  return $pfc.Families[0]
}
$script:collections = @()
$outfitXB = Load-Family "$Root\assets\fonts\Outfit-ExtraBold.ttf"
$urbanMed = Load-Family "$Root\assets\fonts\Urbanist-Medium.ttf"
$urbanSemi = Load-Family "$Root\assets\fonts\Urbanist-SemiBold.ttf"
$urbanBold = Load-Family "$Root\assets\fonts\Urbanist-Bold.ttf"

function C($hex, $a = 255) {
  $h = $hex.TrimStart('#')
  [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16))
}
function Brush($hex, $a = 255) { New-Object System.Drawing.SolidBrush (C $hex $a) }
function Font($family, $px) { New-Object System.Drawing.Font $family, $px, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel) }
function P($x, $y) { New-Object System.Drawing.PointF ([single]$x), ([single]$y) }

function Glyphs($g, $text, $font, $brush, $x, $y, $spacing, [bool]$draw) {
  # GDI+ has no letter-spacing; lay the glyphs out one by one.
  $fmt = [System.Drawing.StringFormat]::GenericTypographic
  foreach ($ch in $text.ToCharArray()) {
    $s = [string]$ch
    if ($s -eq ' ') { $x += $font.Size * 0.3 + $spacing; continue }
    if ($draw) { $g.DrawString($s, $font, $brush, [single]$x, [single]$y, $fmt) }
    $x += $g.MeasureString($s, $font, 10000, $fmt).Width + $spacing
  }
  return $x
}
function TextWidth($g, $text, $font) {
  $g.MeasureString($text, $font, 10000, [System.Drawing.StringFormat]::GenericTypographic).Width
}

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

function New-Canvas($w, $h) {
  $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.TextRenderingHint = 'AntiAliasGridFit'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.PixelOffsetMode = 'HighQuality'
  return $bmp, $g
}

$icon = [System.Drawing.Image]::FromFile("$Root\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_1024.png")
# The icon's rounded square fills 104..920 of the 1024 canvas.
$iconInset = 104 / 1024

function Draw-Icon($g, $x, $y, $size) {
  # $size is the visible rounded square; the PNG's transparent margin is
  # drawn outside it.
  $full = $size / (1 - 2 * $iconInset)
  $off = $full * $iconInset
  $g.DrawImage($icon, [single]($x - $off), [single]($y - $off), [single]$full, [single]$full)
}

# "ALIENSHOT": ALIEN in $alienColor, SHOT in teal. Returns the width.
function Draw-Wordmark($g, $x, $y, $px, $alienHex, $shotHex, [bool]$draw = $true) {
  $f = Font $outfitXB $px
  $track = $px * 0.08
  $x2 = Glyphs $g 'ALIEN' $f (Brush $alienHex) $x $y $track $draw
  $x3 = Glyphs $g 'SHOT' $f (Brush $shotHex) $x2 $y $track $draw
  return $x3 - $track - $x
}

function Draw-Stars($g, $w, $h, $count, $seed) {
  $rng = New-Object System.Random $seed
  for ($i = 0; $i -lt $count; $i++) {
    $x = $rng.NextDouble() * $w; $y = $rng.NextDouble() * $h
    $r = 0.5 + $rng.NextDouble() * 1.4
    $a = [int](35 + $rng.NextDouble() * 120)
    $g.FillEllipse((Brush '#E2F2F6' $a), [single]($x - $r), [single]($y - $r), [single]($r * 2), [single]($r * 2))
  }
}

function Draw-Glow($g, $cx, $cy, $rx, $ry, $hex, $alpha) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddEllipse([single]($cx - $rx), [single]($cy - $ry), [single]($rx * 2), [single]($ry * 2))
  $brush = New-Object System.Drawing.Drawing2D.PathGradientBrush $path
  $brush.CenterColor = C $hex $alpha
  $brush.SurroundColors = @((C $hex 0))
  $g.FillPath($brush, $path)
}

# The product shot: a screen with an area selected Lightshot-style, marked up
# with an arrow and a highlight, and the toolbar under it. Drawn in a
# 520 x 360 design space, placed at ($x, $y) and scaled to $w wide.
function Draw-Mockup($g, $x, $y, $w) {
  $state = $g.Save()
  $s = $w / 520
  $g.TranslateTransform([single]$x, [single]$y)
  $g.ScaleTransform([single]$s, [single]$s)

  # Shadow, then the glass screen.
  for ($i = 1; $i -le 6; $i++) {
    $g.FillPath((Brush '#000000' 14), (RoundRect (-$i * 2 + 6) (14 + $i * 2) (520 + $i * 4 - 12) (360 + $i * 2) 26))
  }
  $screen = RoundRect 0 0 520 360 22
  $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF 0, 0, 520, 360), (C '#0E3540' 246), (C '#072028' 246), 90
  $g.FillPath($fill, $screen)
  $g.SetClip($screen)

  # Window chrome.
  $g.FillRectangle((Brush '#FFFFFF' 14), 0, 0, 520, 34)
  $dot = 0
  foreach ($hex in '#FF5F57', '#FEBC2E', '#28C840') {
    $g.FillEllipse((Brush $hex 230), [single](18 + $dot * 18), 12, 10, 10); $dot++
  }
  $g.FillPath((Brush '#FFFFFF' 20), (RoundRect 170 10 180 14 7))

  # Page content: a hero card, text lines and a chart.
  $g.FillPath((Brush '#E2F2F6' 150), (RoundRect 28 56 170 14 7))
  foreach ($row in @(@(84, 210), @(102, 180), @(120, 196), @(138, 120))) {
    $g.FillPath((Brush '#E2F2F6' 55), (RoundRect 28 $row[0] $row[1] 8 4))
  }
  $img = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF 28, 166, 200, 160), (C '#3FBCC9' 170), (C '#1F6E88' 170), 45
  $g.FillPath($img, (RoundRect 28 166 200 160 12))
  # A little mountain + sun in the picture.
  $g.FillEllipse((Brush '#FFFFFF' 150), 168, 186, 30, 30)
  $g.FillPolygon((Brush '#04141A' 110), [System.Drawing.PointF[]]@((P 28 326), (P 98 236), (P 150 290), (P 182 256), (P 228 326)))

  # The bar chart the user is pointing at.
  $g.FillPath((Brush '#E2F2F6' 140), (RoundRect 262 56 120 12 6))
  $bars = @(48, 82, 64, 118, 96)
  for ($i = 0; $i -lt $bars.Count; $i++) {
    $bh = $bars[$i]
    $hex = if ($i -eq 3) { '#3FBCC9' } else { '#9CC1CA' }
    $g.FillPath((Brush $hex 200), (RoundRect (272 + $i * 44) (206 - $bh) 26 $bh 5))
  }
  $g.FillRectangle((Brush '#E2F2F6' 60), 262, 208, 228, 2)
  foreach ($row in @(@(226, 200), @(244, 150))) {
    $g.FillPath((Brush '#E2F2F6' 55), (RoundRect 262 $row[0] $row[1] 8 4))
  }

  # Everything outside the selection is dimmed.
  $sel = New-Object System.Drawing.RectangleF 250, 46, 250, 220
  $dim = New-Object System.Drawing.Region (New-Object System.Drawing.RectangleF 0, 0, 520, 360)
  $dim.Exclude($sel)
  $g.FillRegion((Brush '#000000' 120), $dim)

  # Markup inside the selection: a highlighter over the tallest bar and an
  # arrow pointing at it.
  $hl = New-Object System.Drawing.Pen (C '#FFD25A' 255), 3.5
  $g.DrawPath($hl, (RoundRect 396 78 48 140 10))
  $arrow = New-Object System.Drawing.Pen (C '#E5484D'), 5
  $arrow.StartCap = 'Round'; $arrow.LineJoin = 'Round'
  $cap = New-Object System.Drawing.Drawing2D.AdjustableArrowCap 3.2, 3.2, $true
  $arrow.CustomEndCap = $cap
  $g.DrawBezier($arrow, (P 300 248), (P 320 200), (P 350 150), (P 388 140))
  $g.DrawString('+42%', (Font $urbanBold 17), (Brush '#E5484D'), [single]282, [single]84)

  $g.ResetClip()

  # Selection frame: teal outline with white corner brackets.
  $g.DrawRectangle((New-Object System.Drawing.Pen (C '#3FBCC9'), 1.6), $sel.X, $sel.Y, $sel.Width, $sel.Height)
  $bracket = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 4
  $bracket.StartCap = 'Round'; $bracket.EndCap = 'Round'; $bracket.LineJoin = 'Round'
  $l = $sel.Left; $t = $sel.Top; $r = $sel.Right; $b = $sel.Bottom; $arm = 18
  foreach ($c in @(@($l, $t, 1, 1), @($r, $t, -1, 1), @($l, $b, 1, -1), @($r, $b, -1, -1))) {
    $cx = $c[0]; $cy = $c[1]; $sx = $c[2]; $sy = $c[3]
    $g.DrawLines($bracket, [System.Drawing.PointF[]]@((P $cx ($cy + $sy * $arm)), (P $cx $cy), (P ($cx + $sx * $arm) $cy)))
  }

  # Size label above the selection.
  $g.FillPath((Brush '#04141A' 220), (RoundRect 250 18 86 22 11))
  $g.DrawString(('1250 ' + [char]0x00D7 + ' 1100'), (Font $urbanSemi 12), (Brush '#E2F2F6'), [single]258, [single]21)

  # Toolbar under the selection.
  $g.FillPath((Brush '#000000' 60), (RoundRect 262 284 238 48 24))
  $g.FillPath((Brush '#F4FBFC' 250), (RoundRect 260 280 238 46 23))
  $ink = New-Object System.Drawing.Pen (C '#04141A' 210), 2.6
  $ink.StartCap = 'Round'; $ink.EndCap = 'Round'; $ink.LineJoin = 'Round'
  $ty = 303
  # pen
  $g.DrawLine($ink, (P 280 ($ty + 7)), (P 292 ($ty - 7)))
  # arrow (active)
  $g.FillEllipse((Brush '#3FBCC9' 70), 302, ($ty - 15), 30, 30)
  $sm = New-Object System.Drawing.Pen (C '#1F97B0'), 2.6
  $sm.StartCap = 'Round'; $sm.LineJoin = 'Round'
  $sm.CustomEndCap = (New-Object System.Drawing.Drawing2D.AdjustableArrowCap 3, 3, $true)
  $g.DrawLine($sm, (P 309 ($ty + 7)), (P 324 ($ty - 7)))
  # rectangle
  $g.DrawRectangle($ink, 342, ($ty - 7), 16, 14)
  # text
  $g.DrawString('T', (Font $urbanBold 19), (Brush '#04141A' 210), [single]369, [single]($ty - 12))
  # colour dot
  $g.FillEllipse((Brush '#E5484D'), 394, ($ty - 8), 16, 16)
  # divider + copy button
  $g.FillRectangle((Brush '#04141A' 40), 422, ($ty - 12), 1.5, 24)
  $g.FillEllipse((Brush '#1F97B0'), 432, ($ty - 17), 56, 34)
  $g.FillPath((Brush '#1F97B0'), (RoundRect 432 ($ty - 17) 58 34 17))
  $g.DrawString('Copy', (Font $urbanBold 14), (Brush '#FFFFFF'), [single]444, [single]($ty - 9))

  # Glass rim on the screen.
  $rim = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF 0, 0, 520, 360), (C '#3FBCC9' 170), (C '#1F97B0' 40), 60
  $g.DrawPath((New-Object System.Drawing.Pen $rim, 1.5), $screen)

  # The pointer, just finishing the drag.
  $cursor = [System.Drawing.PointF[]]@((P 498 262), (P 498 286), (P 504 280), (P 509 291), (P 513 289), (P 508 278), (P 516 278))
  $g.FillPolygon((Brush '#FFFFFF'), $cursor)
  $g.DrawPolygon((New-Object System.Drawing.Pen (C '#04141A'), 1.4), $cursor)

  $g.Restore($state)
}

function Draw-Chip($g, $x, $y, $text, $px) {
  $f = Font $urbanSemi $px
  $tw = TextWidth $g $text $f
  $h = $px * 2.1; $padX = $px * 0.95; $dotR = $px * 0.28
  $w = $padX * 2 + $dotR * 2 + $px * 0.55 + $tw
  $g.FillPath((Brush '#FFFFFF' 22), (RoundRect $x $y $w $h ($h / 2)))
  $g.DrawPath((New-Object System.Drawing.Pen (C '#3FBCC9' 110), 1.2), (RoundRect $x $y $w $h ($h / 2)))
  $g.FillEllipse((Brush '#3FBCC9'), [single]($x + $padX), [single]($y + $h / 2 - $dotR), [single]($dotR * 2), [single]($dotR * 2))
  $g.DrawString($text, $f, (Brush '#E2F2F6'), [single]($x + $padX + $dotR * 2 + $px * 0.55), [single]($y + ($h - $px * 1.2) / 2), [System.Drawing.StringFormat]::GenericTypographic)
  return $w
}

function Chips-Width($g, $texts, $px, $gap) {
  $sum = 0
  foreach ($t in $texts) { $sum += $px * 0.95 * 2 + $px * 0.56 + $px * 0.55 + (TextWidth $g $t (Font $urbanSemi $px)) + $gap }
  return $sum - $gap
}

function Draw-Button($g, $x, $y, $text, $px) {
  $f = Font $urbanBold $px
  $tw = TextWidth $g $text $f
  $h = $px * 2.6; $w = $tw + $px * 3.4
  Draw-Glow $g ($x + $w / 2) ($y + $h / 2) ($w * 0.75) ($h * 1.2) '#3FBCC9' 70
  $rect = New-Object System.Drawing.RectangleF ([single]$x), ([single]$y), ([single]$w), ([single]$h)
  $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, (C '#3FBCC9'), (C '#1F97B0'), 0
  $g.FillPath($fill, (RoundRect $x $y $w $h ($h / 2)))
  $g.DrawString($text, $f, (Brush '#04141A'), [single]($x + $px * 1.7), [single]($y + ($h - $px * 1.22) / 2), [System.Drawing.StringFormat]::GenericTypographic)
  return $w
}

function Draw-Background($g, $w, $h, $grain) {
  $bg = [AdMarble]::Render($w, $h, 46.0, $grain)
  $g.DrawImage($bg, 0, 0, $w, $h)
  $bg.Dispose()
  Draw-Stars $g $w $h ([int]($w * $h / 5200)) 11
}

$headline = 'Capture. Mark up. Done.'
$sub = 'Grab any part of your screen, annotate it and copy it in seconds.'
$chips = @('One hotkey', 'Arrows, shapes & text', 'Windows & macOS')
$site = 'alienwavegroup.com'

New-Item -ItemType Directory -Force "$Out\logo" | Out-Null

# ---------------------------------------------------------------- logos
Copy-Item "$Root\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_1024.png" "$Out\logo\alienshot-icon-1024.png" -Force
Copy-Item "$Root\tool\icons\logo-white.png" "$Out\logo\alienshot-alien-white.png" -Force

foreach ($variant in @(@('dark-background', '#FFFFFF', '#3FBCC9'), @('light-background', '#04141A', '#1F97B0'))) {
  $iconSize = 300; $gap = 70; $px = 210; $pad = 40
  $bmp, $g = New-Canvas 10 10
  $wordW = Draw-Wordmark $g 0 0 $px $variant[1] $variant[2] $false
  $g.Dispose(); $bmp.Dispose()
  $W = [int]($pad * 2 + $iconSize + $gap + $wordW); $H = $iconSize + $pad * 2
  $bmp, $g = New-Canvas $W $H
  Draw-Icon $g $pad $pad $iconSize
  # Outfit's cap height sits ~0.36 em below the em box top.
  $capTop = $px * 0.235; $capH = $px * 0.70
  [void](Draw-Wordmark $g ($pad + $iconSize + $gap) ($pad + $iconSize / 2 - $capTop - $capH / 2) $px $variant[1] $variant[2])
  $g.Dispose()
  $bmp.Save("$Out\logo\alienshot-logo-$($variant[0]).png", [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# ---------------------------------------------------------------- 1200 x 628
$W = 1200; $H = 628
$bmp, $g = New-Canvas $W $H
Draw-Background $g $W $H 420
Draw-Glow $g 900 330 420 300 '#1F97B0' 90
Draw-Icon $g 64 56 58
[void](Draw-Wordmark $g 140 64 34 '#FFFFFF' '#3FBCC9')
$hf = Font $outfitXB 62
$g.DrawString('Capture.', $hf, (Brush '#FFFFFF'), [single]60, [single]150, [System.Drawing.StringFormat]::GenericTypographic)
$g.DrawString('Mark up.', $hf, (Brush '#FFFFFF'), [single]60, [single]222, [System.Drawing.StringFormat]::GenericTypographic)
$g.DrawString('Done.', $hf, (Brush '#3FBCC9'), [single]60, [single]294, [System.Drawing.StringFormat]::GenericTypographic)
$g.DrawString($sub, (Font $urbanMed 22), (Brush '#B5D3DA'), (New-Object System.Drawing.RectangleF 62, 384, 470, 70))
$cx = 62
foreach ($t in $chips) { $cx += (Draw-Chip $g $cx 466 $t 15) + 10 }
$bw = Draw-Button $g 62 532 'Download now' 20
$g.DrawString($site, (Font $urbanSemi 18), (Brush '#9CC1CA'), [single](62 + $bw + 22), [single]551, [System.Drawing.StringFormat]::GenericTypographic)
Draw-Mockup $g 610 130 540
$g.Dispose()
$bmp.Save("$Out\banner-1200x628.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

# ---------------------------------------------------------------- 1080 x 1080
$W = 1080; $H = 1080
$bmp, $g = New-Canvas $W $H
Draw-Background $g $W $H 400
Draw-Glow $g 540 620 450 310 '#1F97B0' 90
$wordPx = 40
$wordW = Draw-Wordmark $g 0 0 $wordPx '#FFFFFF' '#3FBCC9' $false
$x0 = ($W - (66 + 16 + $wordW)) / 2
Draw-Icon $g $x0 64 66
[void](Draw-Wordmark $g ($x0 + 82) 75 $wordPx '#FFFFFF' '#3FBCC9')
$hf = Font $outfitXB 76
$part1 = 'Capture. Mark up. '; $part2 = 'Done.'
$w1 = TextWidth $g $part1 $hf; $w2 = TextWidth $g $part2 $hf
$hx = ($W - $w1 - $w2) / 2
$g.DrawString($part1, $hf, (Brush '#FFFFFF'), [single]$hx, [single]176, [System.Drawing.StringFormat]::GenericTypographic)
$g.DrawString($part2, $hf, (Brush '#3FBCC9'), [single]($hx + $w1), [single]176, [System.Drawing.StringFormat]::GenericTypographic)
$center = New-Object System.Drawing.StringFormat; $center.Alignment = 'Center'
$g.DrawString($sub, (Font $urbanMed 28), (Brush '#B5D3DA'), (New-Object System.Drawing.RectangleF 120, 278, 840, 80), $center)
Draw-Mockup $g 170 368 740
$cw = Chips-Width $g $chips 19 12
$cx = ($W - $cw) / 2
foreach ($t in $chips) { $cx += (Draw-Chip $g $cx 906 $t 19) + 12 }
$bf = Font $urbanBold 24
$bw = (TextWidth $g 'Download now' $bf) + 24 * 3.4
$bw = Draw-Button $g (($W - $bw) / 2 - 130) 976 'Download now' 24
$g.DrawString($site, (Font $urbanSemi 24), (Brush '#9CC1CA'), [single](($W - $bw) / 2 - 130 + $bw + 26), [single]998, [System.Drawing.StringFormat]::GenericTypographic)
$g.Dispose()
$bmp.Save("$Out\banner-1080x1080.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

# ---------------------------------------------------------------- 1080 x 1920
$W = 1080; $H = 1920
$bmp, $g = New-Canvas $W $H
Draw-Background $g $W $H 420
Draw-Glow $g 540 1230 520 420 '#1F97B0' 90
$iconSize = 140
Draw-Icon $g (($W - $iconSize) / 2) 150 $iconSize
$wordW = Draw-Wordmark $g 0 0 56 '#FFFFFF' '#3FBCC9' $false
[void](Draw-Wordmark $g (($W - $wordW) / 2) 322 56 '#FFFFFF' '#3FBCC9')
$hf = Font $outfitXB 104
$lines = @(@('Capture.', '#FFFFFF'), @('Mark up.', '#FFFFFF'), @('Done.', '#3FBCC9'))
for ($i = 0; $i -lt 3; $i++) {
  $tw = TextWidth $g $lines[$i][0] $hf
  $g.DrawString($lines[$i][0], $hf, (Brush $lines[$i][1]), [single](($W - $tw) / 2), [single](440 + $i * 118), [System.Drawing.StringFormat]::GenericTypographic)
}
# Narrow enough that the sentence breaks into two even lines.
$g.DrawString($sub, (Font $urbanMed 34), (Brush '#B5D3DA'), (New-Object System.Drawing.RectangleF 170, 818, 740, 100), $center)
Draw-Mockup $g 90 950 900
$cw = Chips-Width $g $chips 22 12
$cx = ($W - $cw) / 2
foreach ($t in $chips) { $cx += (Draw-Chip $g $cx 1622 $t 22) + 12 }
$bf = Font $urbanBold 32
$bw = (TextWidth $g 'Download now' $bf) + 32 * 3.4
[void](Draw-Button $g (($W - $bw) / 2) 1712 'Download now' 32)
$tw = TextWidth $g $site (Font $urbanSemi 30)
$g.DrawString($site, (Font $urbanSemi 30), (Brush '#9CC1CA'), [single](($W - $tw) / 2), [single]1822, [System.Drawing.StringFormat]::GenericTypographic)
$g.Dispose()
$bmp.Save("$Out\banner-1080x1920.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

$icon.Dispose()
Get-ChildItem $Out -Recurse -File | Select-Object @{n='File';e={$_.FullName.Substring($Out.Length + 1)}}, Length
