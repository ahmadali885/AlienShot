param([string]$Root = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$Out  = "$((Resolve-Path "$PSScriptRoot\..\..").Path)\marketing")
# Renders marketing/hero-mockup-2000x1250.png — the website's "Alien Shot"
# project card mockup: the annotated-screenshot laptop (reusing the same
# device+toolbar art as the tools banner, recoloured to the site's new cyan
# accent) plus the floating UI chips that sit around it on alienwavegroup.com.
# Transparent background — the site supplies its own dark starfield behind it.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

function Load-Family($file) {
  $pfc = New-Object System.Drawing.Text.PrivateFontCollection
  $pfc.AddFontFile($file)
  $script:_pfcs += ,$pfc
  return $pfc.Families[0]
}
$script:_pfcs = @()
$outfitXB  = Load-Family "$Root\assets\fonts\Outfit-ExtraBold.ttf"
$outfitB   = Load-Family "$Root\assets\fonts\Outfit-Bold.ttf"
$urbanMed  = Load-Family "$Root\assets\fonts\Urbanist-Medium.ttf"
$urbanSemi = Load-Family "$Root\assets\fonts\Urbanist-SemiBold.ttf"
$urbanBold = Load-Family "$Root\assets\fonts\Urbanist-Bold.ttf"

function C($hex, $a = 255) {
  $h = $hex.TrimStart('#')
  [System.Drawing.Color]::FromArgb($a,[Convert]::ToInt32($h.Substring(0,2),16),
    [Convert]::ToInt32($h.Substring(2,2),16),[Convert]::ToInt32($h.Substring(4,2),16))
}
function Brush($hex, $a = 255) { New-Object System.Drawing.SolidBrush (C $hex $a) }
function Font($fam, $px)  { New-Object System.Drawing.Font $fam, $px, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel) }
function P($x,$y) { New-Object System.Drawing.PointF ([single]$x),([single]$y) }

function RoundRect($x,$y,$w,$h,$r) {
  $p  = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d  = [math]::Min($r*2,[math]::Min($w,$h))
  $p.AddArc([single]$x,          [single]$y,          [single]$d,[single]$d, 180,90)
  $p.AddArc([single]($x+$w-$d),  [single]$y,          [single]$d,[single]$d, 270,90)
  $p.AddArc([single]($x+$w-$d),  [single]($y+$h-$d),  [single]$d,[single]$d,   0,90)
  $p.AddArc([single]$x,          [single]($y+$h-$d),  [single]$d,[single]$d,  90,90)
  $p.CloseFigure(); return $p
}
function TextWidth($g, $text, $font) {
  $g.MeasureString($text,$font,10000,[System.Drawing.StringFormat]::GenericTypographic).Width
}

# Brand accent — new cyan (was #3FBCC9 / #1F97B0 teal).
$Accent = '#22D3EE'; $AccentDark = '#0891B2'

# ── Load scene (the "content" AlienShot is capturing) ───────────────────────
$scene = [System.Drawing.Image]::FromFile("$PSScriptRoot\scene.png")

function ScX($xl) { [single]($xl / 1440.0 * 600) }
function ScY($yl) { [single](34 + $yl / 900.0 * 366) }

function Draw-AnnotatedMockup($g, $x, $y, $w) {
  $s = $w / 600.0
  $state = $g.Save()
  $g.TranslateTransform([single]$x,[single]$y)
  $g.ScaleTransform([single]$s,[single]$s)

  for ($i=1; $i -le 5; $i++) {
    $g.FillPath((Brush '#000000' 13),(RoundRect (-$i*2+4) (12+$i*2) (600+$i*4-8) (400+$i*2) 24))
  }

  $screen = RoundRect 0 0 600 400 20
  $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
    (New-Object System.Drawing.RectangleF 0,0,600,400),(C '#0E3540' 248),(C '#072028' 248), 90
  $g.FillPath($fill,$screen)
  $g.SetClip($screen)

  $g.FillRectangle((Brush '#FFFFFF' 15),0,0,600,34)
  $dot=0
  foreach ($hex in '#FF5F57','#FEBC2E','#28C840') {
    $g.FillEllipse((Brush $hex 230),[single](18+$dot*18),12,10,10); $dot++
  }
  $g.FillPath((Brush '#FFFFFF' 22),(RoundRect 195 10 210 14 7))

  $g.DrawImage($scene, (New-Object System.Drawing.RectangleF 0,34,600,366),
    (New-Object System.Drawing.RectangleF 0,0,2880,1800),
    [System.Drawing.GraphicsUnit]::Pixel)

  # Highlighter over Revenue KPI.
  $hx1=[single](ScX 262); $hy1=[single](ScY 110); $hw1=[single](ScX(528-262)); $hh1=[single]((ScY 222)-(ScY 110))
  $g.FillRectangle((Brush '#FFD700' 80), $hx1,$hy1,$hw1,$hh1)
  $g.DrawRectangle((New-Object System.Drawing.Pen (C '#FFD700' 200), 3), $hx1,$hy1,$hw1,$hh1)

  # Red bezier arrow at the October bar.
  $arrowPen = New-Object System.Drawing.Pen (C '#E5484D'), 4.5
  $arrowPen.StartCap='Round'; $arrowPen.LineJoin='Round'
  $arrowPen.CustomEndCap=(New-Object System.Drawing.Drawing2D.AdjustableArrowCap 4,4,$true)
  $g.DrawBezier($arrowPen,(P 230 248),(P 310 200),(P 380 155),(P (ScX 853) (ScY 355)))
  $g.DrawString('+58k',(Font $urbanBold 16),(Brush '#E5484D'),[single]196,[single]248,
    [System.Drawing.StringFormat]::GenericTypographic)

  # Accent rectangle around the donut chart.
  $rx1=[single](ScX 1042); $ry1=[single](ScY 242); $rw1=[single](ScX(1416-1042)); $rh1=[single]((ScY 620)-(ScY 242))
  $g.DrawRectangle((New-Object System.Drawing.Pen (C $Accent), 4),$rx1,$ry1,$rw1,$rh1)

  # Green double-arrow baseline.
  $dalPen = New-Object System.Drawing.Pen (C '#3FD42B'), 3.5
  $dalPen.StartCap='Round'
  $dalPen.CustomEndCap=(New-Object System.Drawing.Drawing2D.AdjustableArrowCap 3.5,3.5,$true)
  $dalPen.CustomStartCap=(New-Object System.Drawing.Drawing2D.AdjustableArrowCap 3.5,3.5,$true)
  $g.DrawLine($dalPen,(P (ScX 342) (ScY 608)),(P (ScX 990) (ScY 608)))

  # Pen underline.
  $penLine = New-Object System.Drawing.Pen (C '#2E8BFF'), 3
  $penLine.StartCap='Round'; $penLine.EndCap='Round'
  $g.DrawLine($penLine,(P (ScX 262) (ScY 68)),(P (ScX 660) (ScY 75)))

  # Purple ellipse around Visitors KPI.
  $ex=[single](ScX 830); $ey=[single](ScY 110); $ew=[single](ScX(1096-830)); $eh=[single]((ScY 222)-(ScY 110))
  $g.DrawEllipse((New-Object System.Drawing.Pen (C '#B57CFF'), 4),$ex,$ey,$ew,$eh)

  # "Track this!" label.
  $g.FillPath((Brush '#04141A' 210),(RoundRect (ScX 1100) (ScY 100) 76 22 11))
  $g.DrawString('Track this!',(Font $urbanSemi 12),(Brush '#B57CFF'),
    [single](ScX 1106),[single](ScY 104),[System.Drawing.StringFormat]::GenericTypographic)

  # Star stamp.
  function Star5($gfx,$scx,$scy,$sr,$shex) {
    $spts=[System.Drawing.PointF[]]::new(10)
    for ($k=0;$k -lt 10;$k++) {
      $angle2 = [math]::PI*($k*2-1)/10 - [math]::PI/2
      $rad2   = if ($k%2 -eq 0) {$sr} else {$sr*0.42}
      $spts[$k] = P ($scx+$rad2*[math]::Cos($angle2)) ($scy+$rad2*[math]::Sin($angle2))
    }
    $gfx.FillPolygon((Brush $shex),$spts)
  }
  Star5 $g (ScX 880) (ScY 759) 12 '#FFD700'

  # Check stamp.
  $g.FillEllipse((Brush '#FF8C00' 200),[single]((ScX 880)-12),[single]((ScY 793)-12),24,24)
  $ckPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 3
  $ckPen.StartCap='Round'; $ckPen.EndCap='Round'; $ckPen.LineJoin='Round'
  $g.DrawLines($ckPen,[System.Drawing.PointF[]]@(
    (P ((ScX 874)) ((ScY 793)+1)),(P ((ScX 879)) ((ScY 793)+7)),(P ((ScX 888)) ((ScY 793)-5))))

  # Heart stamp.
  $hcx2=[single](ScX 880); $hcy2=[single](ScY 827)
  $g.FillEllipse((Brush '#FF3FD1' 200),[single]($hcx2-5),[single]($hcy2-9),14,12)
  $g.FillEllipse((Brush '#FF3FD1' 200),[single]($hcx2+2),[single]($hcy2-9),14,12)
  $g.FillPolygon((Brush '#FF3FD1' 200),[System.Drawing.PointF[]]@(
    (P ($hcx2-5) ($hcy2-1)),(P ($hcx2+16) ($hcy2-1)),(P ($hcx2+5.5) ($hcy2+11))))

  # Cross stamp.
  $csPen = New-Object System.Drawing.Pen (C '#E5484D' 220), 4
  $csPen.StartCap='Round'; $csPen.EndCap='Round'
  $g.DrawLine($csPen,(P ((ScX 874)) ((ScY 862)-7)),(P ((ScX 888)) ((ScY 862)+7)))
  $g.DrawLine($csPen,(P ((ScX 888)) ((ScY 862)-7)),(P ((ScX 874)) ((ScY 862)+7)))

  # Selection dim + brackets.
  $srX=[single](ScX 248); $srY=[single](ScY 96)
  $srW=[single](ScX(1430-248)); $srH=[single]((ScY 876)-(ScY 96))
  $selRect = New-Object System.Drawing.RectangleF $srX,$srY,$srW,$srH
  $dimRegion = New-Object System.Drawing.Region (New-Object System.Drawing.RectangleF ([single]0),([single]0),([single]600),([single]400))
  $dimRegion.Exclude($selRect)
  $g.FillRegion((Brush '#000000' 100),$dimRegion)
  $g.DrawRectangle((New-Object System.Drawing.Pen (C $Accent),1.5),
    $selRect.X,$selRect.Y,$selRect.Width,$selRect.Height)
  $brPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White),3.5
  $brPen.StartCap='Round'; $brPen.EndCap='Round'; $brPen.LineJoin='Round'
  $sl=$selRect.Left; $st=$selRect.Top; $sr=$selRect.Right; $sb=$selRect.Bottom; $arm=16
  foreach ($cc in @(@($sl,$st,1,1),@($sr,$st,-1,1),@($sl,$sb,1,-1),@($sr,$sb,-1,-1))) {
    $bcx=$cc[0];$bcy=$cc[1];$bsx=$cc[2];$bsy=$cc[3]
    $g.DrawLines($brPen,[System.Drawing.PointF[]]@((P $bcx ($bcy+$bsy*$arm)),(P $bcx $bcy),(P ($bcx+$bsx*$arm) $bcy)))
  }

  $g.FillPath((Brush '#04141A' 220),(RoundRect (ScX 248) 10 98 20 10))
  $g.DrawString('1184 '+[char]0x00D7+' 780',(Font $urbanSemi 11),(Brush '#E2F2F6'),
    [single]((ScX 254)),[single]13,[System.Drawing.StringFormat]::GenericTypographic)

  $g.ResetClip()

  $rim = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
    (New-Object System.Drawing.RectangleF 0,0,600,400),(C $Accent 160),(C $AccentDark 35), 60
  $g.DrawPath((New-Object System.Drawing.Pen $rim,1.5),$screen)

  # Vertical annotation toolbar.
  $tbX=[single]540; $tbPad=[single]5; $slot=[single]36; $divH=[single]12; $tbW=[single]46
  $tools = @('move','text','draw','stamp','eraser','color','|','undo','redo','clear')
  $tbH = $tbPad*2; foreach ($tt in $tools) { $tbH += if ($tt -eq '|'){$divH}else{$slot} }
  $tbY = [single]((400-$tbH)/2)

  $g.FillPath((Brush '#000000' 30),(RoundRect ($tbX+2) ($tbY+3) $tbW $tbH 23))
  $g.FillPath((Brush '#F4FBFC' 252),(RoundRect $tbX $tbY $tbW $tbH 23))
  $g.DrawPath((New-Object System.Drawing.Pen (C '#CFE4EB'),1),(RoundRect $tbX $tbY $tbW $tbH 23))

  $iy = $tbY + $tbPad
  foreach ($t in $tools) {
    if ($t -eq '|') {
      $g.FillRectangle((Brush '#04141A' 30),[single]($tbX+8),[single]$iy,[single]30,[single]1)
      $iy += $divH; continue
    }
    $cx=[single]($tbX+$tbW/2); $cy=[single]($iy+$slot/2)
    if ($t -eq 'draw') {
      $g.FillPath((Brush $Accent 60),(RoundRect ($tbX+4) ($iy+1) ($tbW-8) ($slot-2) 10))
    }
    $inkHex = if($t -eq 'draw'){$AccentDark}else{'#33444C'}
    $ink = New-Object System.Drawing.Pen (C $inkHex 210), 2.2
    $ink.StartCap='Round'; $ink.EndCap='Round'; $ink.LineJoin='Round'
    switch ($t) {
      'move'   {
        $pts=[System.Drawing.PointF[]]@((P ($cx-7) ($cy-8)),(P ($cx-7) ($cy+7)),(P ($cx-2) ($cy+3)),(P ($cx+5) ($cy+9)),(P ($cx+7) ($cy+7)),(P ($cx+0) ($cy+1)),(P ($cx+4) ($cy-3)))
        $g.FillPolygon((Brush '#33444C' 200),$pts); $g.DrawPolygon($ink,$pts) }
      'text'   { $g.DrawString('T',(Font $urbanBold 21),(Brush '#33444C' 200),[single]($cx-7),[single]($cy-12),[System.Drawing.StringFormat]::GenericTypographic) }
      'draw'   {
        $pPen = New-Object System.Drawing.Pen (C $AccentDark),2.2; $pPen.StartCap='Round';$pPen.EndCap='Round'
        $g.DrawLine($pPen,(P ($cx-7) ($cy+7)),(P ($cx+7) ($cy-7)))
        $g.FillPolygon((Brush $AccentDark),[System.Drawing.PointF[]]@((P ($cx+4) ($cy-10)),(P ($cx+11) ($cy-3)),(P ($cx+7) ($cy-7))))
      }
      'stamp'  {
        $spts=[System.Drawing.PointF[]]::new(10)
        for ($k=0;$k -lt 10;$k++){
          $a=[math]::PI*($k*2-1)/10-[math]::PI/2
          $r2=if($k%2-eq 0){9}else{4}
          $spts[$k]=P ($cx+$r2*[math]::Cos($a)) ($cy+$r2*[math]::Sin($a))
        }
        $g.FillPolygon((Brush '#33444C' 190),$spts)
      }
      'eraser' {
        $g.FillRectangle((Brush '#9CC1CA' 200),[single]($cx-8),[single]($cy-5),16,10)
        $g.DrawRectangle($ink,[single]($cx-8),[single]($cy-5),16,10)
        $g.FillRectangle((Brush '#F4FBFC'),[single]($cx-3),[single]($cy-5),6,10)
      }
      'color'  {
        $colors = @('#FF1F1F','#FFD700','#3FD42B','#2E8BFF','#B57CFF','#FF3FD1')
        for ($ci=0;$ci -lt 6;$ci++){
          $a2=$ci*[math]::PI/3
          $g.FillEllipse((Brush $colors[$ci]),[single]($cx+4*[math]::Cos($a2)-4),[single]($cy+4*[math]::Sin($a2)-4),8,8)
        }
        $g.FillEllipse((Brush '#E5484D'),[single]($cx-5),[single]($cy-5),10,10)
      }
      'undo'   {
        $undoPen = New-Object System.Drawing.Pen (C '#33444C' 200),2.2; $undoPen.StartCap='Round';$undoPen.EndCap='Round'
        $undoPen.CustomEndCap=(New-Object System.Drawing.Drawing2D.AdjustableArrowCap 2.8,2.8,$true)
        $g.DrawArc($undoPen,[single]($cx-8),[single]($cy-8),16,16,140,220)
        $g.DrawLine($undoPen,(P ($cx-5) ($cy-8)),(P ($cx-10) ($cy-11)))
      }
      'redo'   {
        $redoPen = New-Object System.Drawing.Pen (C '#33444C' 200),2.2; $redoPen.StartCap='Round';$redoPen.EndCap='Round'
        $redoPen.CustomEndCap=(New-Object System.Drawing.Drawing2D.AdjustableArrowCap 2.8,2.8,$true)
        $g.DrawArc($redoPen,[single]($cx-8),[single]($cy-8),16,16,-40,-220)
        $g.DrawLine($redoPen,(P ($cx+5) ($cy-8)),(P ($cx+10) ($cy-11)))
      }
      'clear'  {
        $g.DrawRectangle($ink,[single]($cx-6),[single]($cy-6),12,13)
        $g.DrawLine($ink,(P ($cx-9) ($cy-6)),(P ($cx+9) ($cy-6)))
        $g.DrawRectangle($ink,[single]($cx-4),[single]($cy-10),8,4)
        $g.DrawLine($ink,(P ($cx-2) ($cy-4)),(P ($cx-2) ($cy+4)))
        $g.DrawLine($ink,(P ($cx+2) ($cy-4)),(P ($cx+2) ($cy+4)))
      }
    }
    $iy += $slot
  }

  $g.Restore($state)
}

# ── Floating glass chip helper ───────────────────────────────────────────────
function Draw-GlassCard($g,$x,$y,$w,$h,$r) {
  $g.FillPath((Brush '#000000' 60),(RoundRect ($x+3) ($y+5) $w $h $r))
  $g.FillPath((Brush '#0B2A33' 215),(RoundRect $x $y $w $h $r))
  $g.DrawPath((New-Object System.Drawing.Pen (C $Accent 90),1.4),(RoundRect $x $y $w $h $r))
}

# ── Main canvas: 2000×1250, transparent ──────────────────────────────────────
$W=2000; $H=1250
$bmp = New-Object System.Drawing.Bitmap $W,$H,([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode='AntiAlias'; $g.TextRenderingHint='AntiAliasGridFit'
$g.InterpolationMode='HighQualityBicubic'; $g.PixelOffsetMode='HighQuality'

# Laptop base (keyboard deck) under the screen mockup, for a "device" feel.
$lapX=360; $lapY=130; $lapW=1360
Draw-AnnotatedMockup $g $lapX $lapY $lapW
$deckY = $lapY + $lapW*400/600 - 6
$deckW = $lapW*1.08; $deckX = $lapX - ($deckW-$lapW)/2
$g.FillPath((Brush '#000000' 35),(RoundRect $deckX ($deckY+10) $deckW 46 10))
$deckFill = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
  (New-Object System.Drawing.RectangleF $deckX,$deckY,$deckW,40),(C '#D8E4E8'),(C '#A9BAC0'),90
$g.FillPath($deckFill,(RoundRect $deckX $deckY $deckW 40 10))
$g.FillPath((Brush '#8FA3AA'),(RoundRect ($deckX+$deckW/2-70) $deckY 140 10 5))

# Floating chip: hotkey (top-left, overlapping the laptop's top-left corner).
$chipX=60; $chipY=70; $chipW=420; $chipH=130
Draw-GlassCard $g $chipX $chipY $chipW $chipH 20
$g.DrawString('ONE KEY, ONE SHOT',(Font $urbanBold 20) ,(Brush $Accent),[single]($chipX+28),[single]($chipY+20),[System.Drawing.StringFormat]::GenericTypographic)
$keyY=$chipY+58
foreach ($k in @('Ctrl','Shift','S')) {
  $kf = Font $urbanBold 18
  $kw = (TextWidth $g $k $kf)+34
  $g.FillPath((Brush '#133640' 230),(RoundRect $chipX $keyY $kw 40 10))
  $g.DrawPath((New-Object System.Drawing.Pen (C $Accent 120),1.2),(RoundRect $chipX $keyY $kw 40 10))
  $g.DrawString($k,$kf,(Brush '#FFFFFF'),[single]($chipX+17),[single]($keyY+11),[System.Drawing.StringFormat]::GenericTypographic)
  $chipX += $kw+10
}
$g.DrawString('Capture any part of the screen',(Font $urbanMed 17),(Brush '#B5D3DA'),[single]60,[single]($chipY+$chipH-34),[System.Drawing.StringFormat]::GenericTypographic)

# Floating chip: DRAW panel (left-mid, over the laptop's left edge).
$dpX=40; $dpY=300; $dpW=250; $dpH=150
Draw-GlassCard $g $dpX $dpY $dpW $dpH 18
$g.DrawString('DRAW',(Font $urbanBold 16),(Brush $Accent),[single]($dpX+24),[single]($dpY+18),[System.Drawing.StringFormat]::GenericTypographic)
$g.DrawString('SHAPES',(Font $urbanBold 16),(Brush '#6B8A92'),[single]($dpX+130),[single]($dpY+18),[System.Drawing.StringFormat]::GenericTypographic)
$g.FillPath((Brush $Accent 55),(RoundRect ($dpX+16) ($dpY+46) 100 52 14))
$pPen2 = New-Object System.Drawing.Pen (C $AccentDark),4; $pPen2.StartCap='Round'; $pPen2.EndCap='Round'
$g.DrawLine($pPen2,(P ($dpX+40) ($dpY+88)),(P ($dpX+80) ($dpY+58)))
$g.FillPolygon((Brush $AccentDark),[System.Drawing.PointF[]]@((P ($dpX+74) ($dpY+52)),(P ($dpX+92) ($dpY+66)),(P ($dpX+80) ($dpY+58))))
$dotColors=@('#FF1F1F','#FFD700','#3FD42B')
for ($i=0;$i -lt 3;$i++) {
  $g.FillEllipse((Brush $dotColors[$i]),[single]($dpX+24+$i*40),[single]($dpY+114),28,28)
}

# Floating chip: clipboard notification (top-right, over the laptop's top-right).
$ncX=$W-520; $ncY=160; $ncW=460; $ncH=110
Draw-GlassCard $g $ncX $ncY $ncW $ncH 20
$g.FillEllipse((Brush '#3FD42B' 230),[single]($ncX+26),[single]($ncY+30),44,44)
$ckPen2 = New-Object System.Drawing.Pen ([System.Drawing.Color]::White),5; $ckPen2.StartCap='Round'; $ckPen2.EndCap='Round'; $ckPen2.LineJoin='Round'
$g.DrawLines($ckPen2,[System.Drawing.PointF[]]@((P ($ncX+36) ($ncY+52)),(P ($ncX+45) ($ncY+63)),(P ($ncX+62) ($ncY+40))))
$g.DrawString('Link copied to clipboard',(Font $urbanBold 20),(Brush '#FFFFFF'),[single]($ncX+88),[single]($ncY+24),[System.Drawing.StringFormat]::GenericTypographic)
$g.DrawString('files.coffee/mark/fk2j.png — uploaded in 0.4s',(Font $urbanMed 15),(Brush '#9CC1CA'),[single]($ncX+88),[single]($ncY+56),[System.Drawing.StringFormat]::GenericTypographic)

# Floating chip: share bar (bottom, spanning under the laptop's keyboard deck).
$sbW=720; $sbX=($W-$sbW)/2; $sbY=$H-150; $sbH=92
Draw-GlassCard $g $sbX $sbY $sbW $sbH ($sbH/2)
$g.FillEllipse((Brush $Accent 220),[single]($sbX+22),[single]($sbY+22),48,48)
$g.FillPolygon((Brush '#04141A'),[System.Drawing.PointF[]]@((P ($sbX+38) ($sbY+36)),(P ($sbX+38) ($sbY+58)),(P ($sbX+60) ($sbY+47))))
$g.DrawString('Shot captured',(Font $urbanBold 22),(Brush '#FFFFFF'),[single]($sbX+90),[single]($sbY+16),[System.Drawing.StringFormat]::GenericTypographic)
$g.DrawString('2s ago',(Font $urbanMed 16),(Brush '#9CC1CA'),[single]($sbX+90),[single]($sbY+48),[System.Drawing.StringFormat]::GenericTypographic)
$actions=@('Copy','Save','Share link')
$axx=$sbX+330
foreach ($act in $actions) {
  $af=Font $urbanSemi 18; $aw=(TextWidth $g $act $af)+44
  $fillHex = if ($act -eq 'Share link') { $Accent } else { '#133640' }
  $txtHex  = if ($act -eq 'Share link') { '#04141A' } else { '#E2F2F6' }
  $fillA   = if ($act -eq 'Share link') { 255 } else { 220 }
  $g.FillPath((Brush $fillHex $fillA),(RoundRect $axx ($sbY+20) $aw 52 26))
  $g.DrawString($act,$af,(Brush $txtHex),[single]($axx+22),[single]($sbY+34),[System.Drawing.StringFormat]::GenericTypographic)
  $axx += $aw+14
}

$g.Dispose()
New-Item -ItemType Directory -Force $Out | Out-Null
$bmp.Save("$Out\hero-mockup-2000x1250.png",[System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose(); $scene.Dispose()
"Saved: $Out\hero-mockup-2000x1250.png"
