param([string]$OutDir)
Add-Type -AssemblyName System.Drawing
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logo = [System.Drawing.Image]::FromFile("$dir\logo-white.png")
# Tight crop of the alien head (opaque bbox 98..386 x 64..448) with a little air.
$crop = New-Object System.Drawing.Rectangle(90, 56, 304, 400)

function New-RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = 2 * $r
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function Render-Tile([int]$S, [bool]$brackets, [double]$margin) {
  $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
  $g.Clear([System.Drawing.Color]::Transparent)

  $m = [float]($S * $margin); $w = [float]($S - 2 * $m)
  $tile = New-RoundRect $m $m $w $w ([float]($w * 0.23))
  # --grad-deep from the site: #004858 -> #006078 (55%) -> #00323d at 150deg.
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF(($m - 1), ($m - 1))), (New-Object System.Drawing.PointF(($m + $w + 1), ($m + $w + 1))),
    [System.Drawing.Color]::FromArgb(255, 0, 96, 120), [System.Drawing.Color]::FromArgb(255, 0, 40, 50))
  $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
  $blend.Colors = @([System.Drawing.Color]::FromArgb(255, 0, 112, 138), [System.Drawing.Color]::FromArgb(255, 0, 72, 88), [System.Drawing.Color]::FromArgb(255, 0, 40, 50))
  $blend.Positions = @([single]0, [single]0.55, [single]1)
  $brush.InterpolationColors = $blend
  $brush.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipXY
  $g.FillPath($brush, $tile)
  if ($S -ge 48) {
    $rim = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(46, 255, 255, 255), [float]([math]::Max(1, $S / 128)))
    $g.DrawPath($rim, $tile); $rim.Dispose()
  }

  # Alien head, centred; smaller when framed by capture brackets.
  $headH = if ($brackets) { $w * 0.50 } else { $w * 0.66 }
  $headW = $headH * $crop.Width / $crop.Height
  $hx = $m + ($w - $headW) / 2; $hy = $m + ($w - $headH) / 2
  $g.DrawImage($logo, (New-Object System.Drawing.RectangleF($hx, $hy, $headW, $headH)), $crop, [System.Drawing.GraphicsUnit]::Pixel)

  if ($brackets) {
    # Capture-frame corners in white, like the alien.
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [float]($w * 0.05))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $in = $m + $w * 0.17; $out = $m + $w * 0.83; $arm = $w * 0.15
    foreach ($c in @(@($in, $in, 1, 1), @($out, $in, -1, 1), @($in, $out, 1, -1), @($out, $out, -1, -1))) {
      $cx = [float]$c[0]; $cy = [float]$c[1]; $sx = $c[2]; $sy = $c[3]
      $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF($cx, ($cy + $sy * $arm))),
        (New-Object System.Drawing.PointF($cx, $cy)),
        (New-Object System.Drawing.PointF(($cx + $sx * $arm), $cy)))
      $g.DrawLines($pen, $pts)
    }
    $pen.Dispose()
  }
  $g.Dispose(); $brush.Dispose(); $tile.Dispose()
  return $bmp
}

function Save-Png($bmp, $path) { $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) }

function Write-Ico([string]$path, [object[]]$entries) {
  # entries: @{ Size = n; Png = byte[] } — PNG-compressed ICO (Vista+).
  $ms = New-Object System.IO.MemoryStream; $bw = New-Object System.IO.BinaryWriter($ms)
  $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$entries.Count)
  $offset = 6 + 16 * $entries.Count
  foreach ($e in $entries) {
    $dim = if ($e.Size -ge 256) { 0 } else { $e.Size }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$e.Png.Length); $bw.Write([uint32]$offset)
    $offset += $e.Png.Length
  }
  foreach ($e in $entries) { $bw.Write($e.Png) }
  $bw.Flush(); [System.IO.File]::WriteAllBytes($path, $ms.ToArray()); $bw.Dispose()
}

function Png-Bytes($bmp) { $ms = New-Object System.IO.MemoryStream; $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); return ,$ms.ToArray() }

# Classic ICO entry: 32-bit BGRA DIB (bottom-up) followed by an all-zero AND
# mask. GDI paths that load small icons don't decode PNG-compressed entries,
# so only the 256px image is stored as PNG.
function Dib-Bytes($bmp) {
  $w = $bmp.Width; $h = $bmp.Height
  $andStride = [int]([math]::Ceiling($w / 32)) * 4
  $ms = New-Object System.IO.MemoryStream; $bw = New-Object System.IO.BinaryWriter($ms)
  $bw.Write([uint32]40); $bw.Write([int32]$w); $bw.Write([int32]($h * 2)); $bw.Write([uint16]1); $bw.Write([uint16]32)
  $bw.Write([uint32]0); $bw.Write([uint32]($w * $h * 4 + $andStride * $h)); $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([uint32]0); $bw.Write([uint32]0)
  $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
  $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $buf = New-Object byte[] ($data.Stride * $h)
  [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
  $stride = $data.Stride; $bmp.UnlockBits($data)
  for ($y = $h - 1; $y -ge 0; $y--) { $bw.Write($buf, $y * $stride, $w * 4) }
  $bw.Write((New-Object byte[] ($andStride * $h)))
  $bw.Flush(); return ,$ms.ToArray()
}

function Icon-Bytes($bmp) { if ($bmp.Width -ge 256) { return ,(Png-Bytes $bmp) } else { return ,(Dib-Bytes $bmp) } }

New-Item -ItemType Directory -Force $OutDir | Out-Null

# Windows app icon: brackets from 48px up, plain alien below that.
$app = @()
foreach ($s in 16, 20, 24, 32, 40, 48, 64, 128, 256) {
  $b = Render-Tile $s ($s -ge 48) 0.03
  $app += @{ Size = $s; Png = (Icon-Bytes $b) }
  if ($s -eq 256) { Save-Png $b "$OutDir\app_icon_256.png" }
  $b.Dispose()
}
Write-Ico "$OutDir\app_icon.ico" $app

# Tray icon: plain alien tile, small sizes only.
$tray = @()
foreach ($s in 16, 20, 24, 32, 40, 48, 64) { $b = Render-Tile $s $false 0.02; $tray += @{ Size = $s; Png = (Icon-Bytes $b) }; $b.Dispose() }
Write-Ico "$OutDir\tray_icon.ico" $tray
$b = Render-Tile 64 $false 0.02; Save-Png $b "$OutDir\tray_icon.png"; $b.Dispose()

# Tray icon while recording: the same tile with a red dot at the bottom right.
$recording = @()
foreach ($s in 16, 20, 24, 32, 40, 48, 64) {
  $b = Render-Tile $s $false 0.02
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.SmoothingMode = 'AntiAlias'
  $d = [float]($s * 0.5); $x = [float]($s - $d); $y = [float]($s - $d)
  $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)), $x - 1, $y - 1, $d + 1, $d + 1)
  $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 229, 72, 77))), $x, $y, $d - 1, $d - 1)
  $g.Dispose()
  $recording += @{ Size = $s; Png = (Icon-Bytes $b) }
  $b.Dispose()
}
Write-Ico "$OutDir\tray_icon_recording.ico" $recording

# macOS app icon set: Big Sur style keeps ~10% transparent margin around the tile.
foreach ($s in 16, 32, 64, 128, 256, 512, 1024) { $b = Render-Tile $s ($s -ge 64) 0.10; Save-Png $b "$OutDir\mac_app_icon_$s.png"; $b.Dispose() }

$logo.Dispose()
Get-ChildItem $OutDir | Select-Object Name, Length | Format-Table -AutoSize | Out-String
