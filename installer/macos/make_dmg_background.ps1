param([string]$Root = (Resolve-Path "$PSScriptRoot\..\..").Path, [string]$Out = $PSScriptRoot)
# Renders installer/macos/dmg-background(@2x).png, the macOS DMG window
# background (680x420 pt): the app's hero.frag marble (ported to C#) as a
# starry night, with a glass tile for the app and one for Applications.
# Run on Windows PowerShell.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// CPU port of shaders/hero.frag (dark branch), frozen at one moment.
public static class Marble {
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

  public static Bitmap Render(int w, int h, double time) {
    var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    var px = new byte[data.Stride * h];
    double t = time * 0.045;
    for (int j = 0; j < h; j++) {
      for (int i = 0; i < w; i++) {
        double u = (i + 0.5) / w, v = (h - (j + 0.5)) / h;
        double x = u * w / h, y = v;
        double qx = Fbm(x + t, y + t), qy = Fbm(x + 5.2 - t, y + 1.3 - t);
        double rx = Fbm(x + 2 * qx + 1.7, y + 2 * qy + 9.2);
        double ry = Fbm(x + 2 * qx + 8.3 - t, y + 2 * qy + 2.8 - t);
        double f = Fbm(x + 2 * rx, y + 2 * ry);

        double s1 = Smooth(-0.25, 0.6, f), s2 = Smooth(0.15, 0.95, rx);
        double s3 = Math.Pow(Smooth(0.5, 1.0, f + ry * 0.35), 1.7) * 0.8;
        double cr = Mix(Mix(Mix(0.016, 0.0, s1), 0.0, s2), 0.122, s3);
        double cg = Mix(Mix(Mix(0.078, 0.282, s1), 0.372, s2), 0.592, s3);
        double cb = Mix(Mix(Mix(0.094, 0.345, s1), 0.454, s2), 0.690, s3);

        double lx = u - 0.62, ly = v - 0.45;
        double vig = Smooth(1.45, 0.1, Math.Sqrt(lx * lx + ly * ly));
        double k = 0.72 + 0.5 * vig;
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

function C($hex, $a = 255) {
  $h = $hex.TrimStart('#')
  [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16))
}

function Glyphs($g, $text, $font, $brush, $x, $y, $spacing, [bool]$draw) {
  # GDI+ has no letter-spacing; lay the glyphs out one by one.
  $fmt = [System.Drawing.StringFormat]::GenericTypographic
  foreach ($ch in $text.ToCharArray()) {
    $s = [string]$ch
    # A lone space measures zero wide (trailing whitespace is trimmed).
    if ($s -eq ' ') { $x += $font.Size * 0.3 + $spacing; continue }
    if ($draw) { $g.DrawString($s, $font, $brush, $x, $y, $fmt) }
    $x += $g.MeasureString($s, $font, 1000, $fmt).Width + $spacing
  }
  return $x
}

function RoundRect($x, $y, $w, $h, $r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function Render($scale, $out) {
  $W = 680; $H = 420
  $bmp = [Marble]::Render([int]($W * $scale), [int]($H * $scale), 46.0)
  $bmp.SetResolution(72 * $scale, 72 * $scale)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.TextRenderingHint = 'AntiAliasGridFit'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.ScaleTransform($scale, $scale)

  # Deepen the edges so the centre glows.
  $edge = New-Object System.Drawing.Drawing2D.GraphicsPath
  $edge.AddEllipse(-180, -160, $W + 360, $H + 320)
  $vignette = New-Object System.Drawing.Drawing2D.PathGradientBrush $edge
  $vignette.CenterColor = C '#000000' 0
  $vignette.SurroundColors = @((C '#02090C' 200))
  $g.FillRectangle($vignette, -2, -2, $W + 4, $H + 4)

  # A teal glow behind the two tiles.
  $glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
  $glowPath.AddEllipse(90, 90, 500, 270)
  $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush $glowPath
  $glow.CenterColor = C '#1F97B0' 70
  $glow.SurroundColors = @((C '#1F97B0' 0))
  $g.FillPath($glow, $glowPath)

  # Faint stars: AlienWave is a space brand. Seeded, so every render matches.
  $rng = New-Object System.Random 7
  for ($i = 0; $i -lt 90; $i++) {
    $x = $rng.NextDouble() * $W; $y = $rng.NextDouble() * $H
    $r = 0.4 + $rng.NextDouble() * 1.0
    $a = [int](40 + $rng.NextDouble() * 120)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush (C '#E2F2F6' $a)), [single]($x - $r), [single]($y - $r), [single]($r * 2), [single]($r * 2))
  }

  # Header: icon + wordmark, then the tagline.
  $wfont = New-Object System.Drawing.Font $outfitXB, 24, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $track = 24 * 0.08
  $wordW = (Glyphs $g 'ALIENSHOT' $wfont $null 0 0 $track $false) - $track
  $logoSize = 32; $gap = 11
  $x0 = ($W - ($logoSize + $gap + $wordW)) / 2
  $logo = [System.Drawing.Image]::FromFile("$Root\assets\images\app_logo.png")
  $g.DrawImage($logo, [single]$x0, [single]26, [single]$logoSize, [single]$logoSize)
  $logo.Dispose()
  $x = Glyphs $g 'ALIEN' $wfont ([System.Drawing.Brushes]::White) ($x0 + $logoSize + $gap) 28 $track $true
  [void](Glyphs $g 'SHOT' $wfont (New-Object System.Drawing.SolidBrush (C '#3FBCC9')) $x 28 $track $true)

  $center = New-Object System.Drawing.StringFormat
  $center.Alignment = 'Center'
  $tagline = New-Object System.Drawing.Font $urbanMed, 13.5, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString('Drag AlienShot onto Applications to install', $tagline, (New-Object System.Drawing.SolidBrush (C '#9CC1CA')), (New-Object System.Drawing.RectangleF 0, 68, $W, 20), $center)

  # Two glass tiles. Finder writes the icon names itself — black in light
  # mode, white in dark — and they land on these tiles, so the glass is a
  # mid-tone teal both read on (~4.5:1 either way).
  # Icons sit at (190, 222) and (490, 222).
  foreach ($cx in 190, 490) {
    $tx = $cx - 100; $ty = 118; $tw = 200; $th = 202
    $shadow = RoundRect ($tx + 2) ($ty + 10) $tw $th 30
    $g.FillPath((New-Object System.Drawing.SolidBrush (C '#000000' 80)), $shadow)
    $tile = RoundRect $tx $ty $tw $th 30
    $span = New-Object System.Drawing.RectangleF $tx, ($ty - 2), $tw, ($th + 4)
    $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush $span, (C '#2C6E7B' 240), (C '#3A8794' 240), 90
    $g.FillPath($fill, $tile)
    $sheen = New-Object System.Drawing.Drawing2D.LinearGradientBrush $span, (C '#FFFFFF' 34), (C '#FFFFFF' 0), 90
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
    $blend.Colors = @((C '#FFFFFF' 34), (C '#FFFFFF' 0), (C '#FFFFFF' 0))
    $blend.Positions = @([single]0, [single]0.5, [single]1)
    $sheen.InterpolationColors = $blend
    $g.FillPath($sheen, $tile)
    # Gradient rim in the brand's accent colours.
    $rimBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $span, (C '#3FBCC9' 200), (C '#1F97B0' 90), 60
    $g.DrawPath((New-Object System.Drawing.Pen $rimBrush, 1.5), $tile)
  }

  # The app inside a capture frame — the logo's corner brackets.
  $bracket = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 3.5
  $bracket.StartCap = 'Round'; $bracket.EndCap = 'Round'; $bracket.LineJoin = 'Round'
  $l = 128; $t = 158; $r = 252; $b = 278; $arm = 20
  foreach ($c in @(@($l, $t, 1, 1), @($r, $t, -1, 1), @($l, $b, 1, -1), @($r, $b, -1, -1))) {
    $cx = [single]$c[0]; $cy = [single]$c[1]; $sx = $c[2]; $sy = $c[3]
    $g.DrawLines($bracket, [System.Drawing.PointF[]]@(
      (New-Object System.Drawing.PointF $cx, ($cy + $sy * $arm)),
      (New-Object System.Drawing.PointF $cx, $cy),
      (New-Object System.Drawing.PointF ($cx + $sx * $arm), $cy)))
  }

  # Applications inside a dashed drop zone.
  $zone = RoundRect 430 160 120 116 22
  $dash = New-Object System.Drawing.Pen (C '#FFFFFF' 165), 2
  $dash.DashPattern = @([single]3, [single]3)
  $g.DrawPath($dash, $zone)

  # A bold glowing arrow between the tiles.
  $ay = 219
  $p0 = New-Object System.Drawing.PointF 304, $ay
  $p1 = New-Object System.Drawing.PointF 368, $ay
  foreach ($layer in @(@(18, 26), @(12, 46), @(8, 80))) {
    $gp = New-Object System.Drawing.Pen (C '#3FBCC9' $layer[1]), $layer[0]
    $gp.StartCap = 'Round'; $gp.EndCap = 'Round'
    $g.DrawLine($gp, $p0, $p1)
  }
  $shaftBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF 300, ($ay - 4), 80, 8), (C '#BDEFF4'), ([System.Drawing.Color]::White), 0
  $shaft = New-Object System.Drawing.Pen $shaftBrush, 5
  $shaft.StartCap = 'Round'; $shaft.EndCap = 'Round'
  $g.DrawLine($shaft, $p0, $p1)
  $head = New-Object System.Drawing.Drawing2D.GraphicsPath
  $head.AddPolygon([System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF 362, ($ay - 13)),
    (New-Object System.Drawing.PointF 382, $ay),
    (New-Object System.Drawing.PointF 362, ($ay + 13))))
  $g.FillPath((New-Object System.Drawing.SolidBrush (C '#3FBCC9' 70)), $head)
  $headPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 4.5
  $headPen.LineJoin = 'Round'; $headPen.StartCap = 'Round'; $headPen.EndCap = 'Round'
  $g.DrawLines($headPen, [System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF 364, ($ay - 12)),
    (New-Object System.Drawing.PointF 380, $ay),
    (New-Object System.Drawing.PointF 364, ($ay + 12))))

  # Footer: what to do if Gatekeeper stops the first launch, and who made it.
  $tipBold = New-Object System.Drawing.Font $urbanSemi, 11.5, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $tip = New-Object System.Drawing.Font $urbanMed, 11.5, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $sep = '  ' + [char]0x203A + '  '
  $g.DrawString('Blocked on first launch?', $tipBold, ([System.Drawing.Brushes]::White), (New-Object System.Drawing.RectangleF 0, 336, $W, 16), $center)
  $g.DrawString("System Settings${sep}Privacy & Security${sep}Open Anyway", $tip, (New-Object System.Drawing.SolidBrush (C '#9CC1CA')), (New-Object System.Drawing.RectangleF 0, 352, $W, 16), $center)
  $small = New-Object System.Drawing.Font $urbanMed, 10, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString('by AlienWave  ' + [char]0x00B7 + '  alienwavegroup.com', $small, (New-Object System.Drawing.SolidBrush (C '#6F8F98')), (New-Object System.Drawing.RectangleF 0, 374, $W, 14), $center)

  $g.Dispose()
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

New-Item -ItemType Directory -Force $Out | Out-Null
Render 1 "$Out\dmg-background.png"
Render 2 "$Out\dmg-background@2x.png"
'done'
