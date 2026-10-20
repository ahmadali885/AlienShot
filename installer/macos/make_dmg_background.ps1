param([string]$Root = (Resolve-Path "$PSScriptRoot\..\..").Path, [string]$Out = $PSScriptRoot)
# Renders installer/macos/dmg-background(@2x).png, the macOS DMG window
# background (660x400 pt), in the app's dark theme: the hero.frag marble
# (ported to C#) under a teal glass card. Run on Windows PowerShell.
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
  $W = 660; $H = 400
  $bmp = [Marble]::Render([int]($W * $scale), [int]($H * $scale), 30.0)
  $bmp.SetResolution(72 * $scale, 72 * $scale)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.TextRenderingHint = 'AntiAliasGridFit'
  $g.ScaleTransform($scale, $scale)

  # Wordmark, as in the app's title bar: white "ALIEN", accent "SHOT".
  $wfont = New-Object System.Drawing.Font $outfitXB, 30, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $track = 30 * 0.08
  $total = (Glyphs $g 'ALIENSHOT' $wfont $null 0 0 $track $false) - $track
  $x = ($W - $total) / 2
  $x = Glyphs $g 'ALIEN' $wfont ([System.Drawing.Brushes]::White) $x 30 $track $true
  [void](Glyphs $g 'SHOT' $wfont (New-Object System.Drawing.SolidBrush (C '#3FBCC9')) $x 30 $track $true)

  $center = New-Object System.Drawing.StringFormat
  $center.Alignment = 'Center'
  $sub = New-Object System.Drawing.Font $urbanMed, 15, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString('Drag AlienShot into your Applications folder', $sub, (New-Object System.Drawing.SolidBrush (C '#8FB3BC')), (New-Object System.Drawing.RectangleF 0, 76, $W, 24), $center)

  # Glass card holding the two icons. Finder draws the icon names itself, in
  # black (light mode) or white (dark mode), and they sit on this card — so
  # it's a mid-tone teal both read on (~4.5:1 either way), unlike the app's
  # near-black glass.
  $card = RoundRect 70 112 520 190 24
  $shadow = RoundRect 70 122 520 190 24
  $g.FillPath((New-Object System.Drawing.SolidBrush (C '#000000' 70)), $shadow)
  # Brushes span a little past the card: GDI+ tiles a gradient beyond its end
  # points, which showed up as hard bands across the card.
  $span = New-Object System.Drawing.RectangleF 70, 110, 520, 196
  $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush $span, (C '#2A6A77' 238), (C '#3B8896' 238), 90
  $g.FillPath($fill, $card)
  $sheen = New-Object System.Drawing.Drawing2D.LinearGradientBrush $span, (C '#FFFFFF' 26), (C '#FFFFFF' 0), 90
  $blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
  $blend.Colors = @((C '#FFFFFF' 28), (C '#FFFFFF' 0), (C '#FFFFFF' 0))
  $blend.Positions = @([single]0, [single]0.45, [single]1)
  $sheen.InterpolationColors = $blend
  $g.FillPath($sheen, $card)
  $g.DrawPath((New-Object System.Drawing.Pen (C '#FFFFFF' 60), 1), $card)

  # Dotted drag path from the app towards Applications, then a chevron.
  $ay = 200
  $n = 9
  for ($i = 0; $i -lt $n; $i++) {
    $t = $i / ($n - 1)
    $cx = 254 + $i * 16
    $g.FillEllipse((New-Object System.Drawing.SolidBrush (C '#FFFFFF' ([int](70 + 185 * $t)))), [single]($cx - 3), [single]($ay - 3), 6, 6)
  }
  $head = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 5
  $head.StartCap = 'Round'; $head.EndCap = 'Round'; $head.LineJoin = 'Round'
  $g.DrawLines($head, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 396, ($ay - 14)), (New-Object System.Drawing.PointF 410, $ay), (New-Object System.Drawing.PointF 396, ($ay + 14))))

  # First-launch tip: the app isn't notarised, so Gatekeeper stops it once.
  $tipBold = New-Object System.Drawing.Font $urbanSemi, 12, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $tip = New-Object System.Drawing.Font $urbanMed, 12, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $sep = '  ' + [char]0x203A + '  '
  $g.DrawString('Blocked on first launch?', $tipBold, ([System.Drawing.Brushes]::White), (New-Object System.Drawing.RectangleF 0, 316, $W, 18), $center)
  $g.DrawString("System Settings${sep}Privacy & Security${sep}Open Anyway", $tip, (New-Object System.Drawing.SolidBrush (C '#8FB3BC')), (New-Object System.Drawing.RectangleF 0, 334, $W, 18), $center)

  $g.Dispose()
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

New-Item -ItemType Directory -Force $Out | Out-Null
Render 1 "$Out\dmg-background.png"
Render 2 "$Out\dmg-background@2x.png"
'done'
