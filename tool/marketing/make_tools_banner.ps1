param([string]$Root = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$Out  = "$((Resolve-Path "$PSScriptRoot\..\..").Path)\marketing")
# Renders marketing/banner-tools-1200x628.png  – a single ad that shows every
# AlienShot annotation tool in action on a real-looking dashboard screenshot.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

# ── Marble background (same shader as the main ads) ─────────────────────────
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class TBMarble {
  static double Fract(double x){return x-Math.Floor(x);}
  static void Hash(double px,double py,out double hx,out double hy){
    hx=-1+2*Fract(Math.Sin(px*127.1+py*311.7)*43758.5453123);
    hy=-1+2*Fract(Math.Sin(px*269.5+py*183.3)*43758.5453123);}
  static double Noise(double x,double y){
    double ix=Math.Floor(x),iy=Math.Floor(y),fx=x-ix,fy=y-iy;
    double ux=fx*fx*(3-2*fx),uy=fy*fy*(3-2*fy);
    double ax,ay,bx,by,cx,cy,dx,dy;
    Hash(ix,iy,out ax,out ay);Hash(ix+1,iy,out bx,out by);
    Hash(ix,iy+1,out cx,out cy);Hash(ix+1,iy+1,out dx,out dy);
    double d0=ax*fx+ay*fy,d1=bx*(fx-1)+by*fy,d2=cx*fx+cy*(fy-1),d3=dx*(fx-1)+dy*(fy-1);
    double a=d0+(d1-d0)*ux,b=d2+(d3-d2)*ux; return a+(b-a)*uy;}
  static double Fbm(double x,double y){double v=0,a=0.5;for(int i=0;i<5;i++){v+=a*Noise(x,y);x*=2;y*=2;a*=0.5;}return v;}
  static double Smooth(double e0,double e1,double x){double t=Math.Max(0,Math.Min(1,(x-e0)/(e1-e0)));return t*t*(3-2*t);}
  static double Mix(double a,double b,double t){return a+(b-a)*t;}
  public static Bitmap Render(int w,int h,double time,double scale){
    var bmp=new Bitmap(w,h,PixelFormat.Format32bppArgb);
    var data=bmp.LockBits(new Rectangle(0,0,w,h),ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);
    var px=new byte[data.Stride*h]; double t=time*0.045;
    for(int j=0;j<h;j++){for(int i=0;i<w;i++){
      double x=(i+0.5)/scale,y=(h-(j+0.5))/scale;
      double qx=Fbm(x+t,y+t),qy=Fbm(x+5.2-t,y+1.3-t);
      double rx=Fbm(x+2*qx+1.7,y+2*qy+9.2),ry=Fbm(x+2*qx+8.3-t,y+2*qy+2.8-t);
      double f=Fbm(x+2*rx,y+2*ry);
      double s1=Smooth(-0.25,0.6,f),s2=Smooth(0.15,0.95,rx),s3=Math.Pow(Smooth(0.5,1.0,f+ry*0.35),1.7)*0.8;
      double cr=Mix(Mix(Mix(0.016,0.0,s1),0.0,s2),0.122,s3);
      double cg=Mix(Mix(Mix(0.078,0.282,s1),0.372,s2),0.592,s3);
      double cb=Mix(Mix(Mix(0.094,0.345,s1),0.454,s2),0.690,s3);
      double u=(i+0.5)/w,v=(j+0.5)/h; double lx=u-0.6,ly=v-0.5;
      double vig=Smooth(1.2,0.1,Math.Sqrt(lx*lx+ly*ly)); double k=0.74+0.55*vig;
      int o=j*data.Stride+i*4;
      px[o]=(byte)Math.Min(255,cb*k*255);px[o+1]=(byte)Math.Min(255,cg*k*255);
      px[o+2]=(byte)Math.Min(255,cr*k*255);px[o+3]=255;}}
    System.Runtime.InteropServices.Marshal.Copy(px,0,data.Scan0,px.Length);
    bmp.UnlockBits(data); return bmp;}}
"@

# ── Font helpers ─────────────────────────────────────────────────────────────
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
function Pen($hex, $w = 1, $a = 255)   { New-Object System.Drawing.Pen (C $hex $a), ([single]$w) }
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
function Glyphs($g, $text, $font, $brush, $x, $y, $track) {
  $fmt = [System.Drawing.StringFormat]::GenericTypographic
  foreach ($ch in $text.ToCharArray()) {
    $s = [string]$ch
    if ($s -eq ' ') { $x += $font.Size*0.3+$track; continue }
    $g.DrawString($s,$font,$brush,[single]$x,[single]$y,$fmt)
    $x += $g.MeasureString($s,$font,10000,$fmt).Width+$track
  }
}

function Draw-Stars($g,$w,$h,$count,$seed) {
  $rng = New-Object System.Random $seed
  for ($i=0; $i -lt $count; $i++) {
    $x=$rng.NextDouble()*$w; $y=$rng.NextDouble()*$h
    $r=0.5+$rng.NextDouble()*1.4; $a=[int](30+$rng.NextDouble()*100)
    $g.FillEllipse((Brush '#E2F2F6' $a),[single]($x-$r),[single]($y-$r),[single]($r*2),[single]($r*2))
  }
}

function Draw-Glow($g,$cx,$cy,$rx,$ry,$hex,$alpha) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddEllipse([single]($cx-$rx),[single]($cy-$ry),[single]($rx*2),[single]($ry*2))
  $br = New-Object System.Drawing.Drawing2D.PathGradientBrush $path
  $br.CenterColor = C $hex $alpha; $br.SurroundColors = @((C $hex 0))
  $g.FillPath($br,$path)
}

# ── Load icon and scene ──────────────────────────────────────────────────────
$appIcon  = [System.Drawing.Image]::FromFile("$Root\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_1024.png")
$iconInset = 104/1024
function Draw-Icon($g,$x,$y,$size) {
  $full = $size/(1-2*$iconInset); $off = $full*$iconInset
  $g.DrawImage($appIcon,[single]($x-$off),[single]($y-$off),[single]$full,[single]$full)
}
function Draw-Wordmark($g,$x,$y,$px,$alienHex,$shotHex) {
  $f=$f2=(Font $outfitXB $px); $track=$px*0.08
  Glyphs $g 'ALIEN' $f  (Brush $alienHex) $x $y $track
  $x2=$x+(TextWidth $g 'ALIEN' $f)+5*$track
  Glyphs $g 'SHOT'  $f2 (Brush $shotHex)  $x2 $y $track
}

$scene = [System.Drawing.Image]::FromFile("$PSScriptRoot\scene.png")
# scene.png is 2880×1800 pixels = 1440×900 logical (drawn at 2× scale)

# ── Annotated mockup ─────────────────────────────────────────────────────────
# Design space: 600 wide × 400 tall. Screen area below 34px chrome = 600×366.
# Scene (1440×900 logical) → scale to 600×375, crop 9px bottom.
# Conversion: logical→design:  sx = x_l/1440*600,  sy = 34 + y_l/900*366
function ScX($xl) { [single]($xl / 1440.0 * 600) }
function ScY($yl) { [single](34 + $yl / 900.0 * 366) }

function Draw-AnnotatedMockup($g, $x, $y, $w) {
  $s = $w / 600.0
  $state = $g.Save()
  $g.TranslateTransform([single]$x,[single]$y)
  $g.ScaleTransform([single]$s,[single]$s)

  # Drop shadow.
  for ($i=1; $i -le 5; $i++) {
    $g.FillPath((Brush '#000000' 13),(RoundRect (-$i*2+4) (12+$i*2) (600+$i*4-8) (400+$i*2) 24))
  }

  # Screen background.
  $screen = RoundRect 0 0 600 400 20
  $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
    (New-Object System.Drawing.RectangleF 0,0,600,400),(C '#0E3540' 248),(C '#072028' 248), 90
  $g.FillPath($fill,$screen)
  $g.SetClip($screen)

  # Browser chrome bar.
  $g.FillRectangle((Brush '#FFFFFF' 15),0,0,600,34)
  $dot=0
  foreach ($hex in '#FF5F57','#FEBC2E','#28C840') {
    $g.FillEllipse((Brush $hex 230),[single](18+$dot*18),12,10,10); $dot++
  }
  $g.FillPath((Brush '#FFFFFF' 22),(RoundRect 195 10 210 14 7))

  # Draw the scene (scale 600/1440 × 366/900 — slightly non-uniform, fine for a mock).
  $g.DrawImage($scene, (New-Object System.Drawing.RectangleF 0,34,600,366),
    (New-Object System.Drawing.RectangleF 0,0,2880,1800),
    [System.Drawing.GraphicsUnit]::Pixel)

  # ── Annotations ─────────────────────────────────────────────────────────────

  # 1. Yellow highlighter tint over Revenue KPI card  (logical: 262–528, 110–222)
  $hx1=[single](ScX 262); $hy1=[single](ScY 110); $hw1=[single](ScX(528-262)); $hh1=[single]((ScY 222)-(ScY 110))
  $g.FillRectangle((Brush '#FFD700' 80), $hx1,$hy1,$hw1,$hh1)
  $hlPen = New-Object System.Drawing.Pen (C '#FFD700' 200), 3
  $g.DrawRectangle($hlPen, $hx1,$hy1,$hw1,$hh1)

  # 2. Red bezier arrow pointing at October bar (index 9, highest: ~$48k)
  #    Bar top logical: x_center ≈ 334+9*56+15 = 853, y_top ≈ 345
  $arrowPen = New-Object System.Drawing.Pen (C '#E5484D'), 4.5
  $arrowPen.StartCap='Round'; $arrowPen.LineJoin='Round'
  $cap = New-Object System.Drawing.Drawing2D.AdjustableArrowCap 4,4,$true
  $arrowPen.CustomEndCap=$cap
  $g.DrawBezier($arrowPen,(P 230 248),(P 310 200),(P 380 155),(P (ScX 853) (ScY 355)))

  # 3. Red "+58k" text label at start of arrow
  $g.DrawString('+58k',(Font $urbanBold 16),(Brush '#E5484D'),[single]196,[single]248,
    [System.Drawing.StringFormat]::GenericTypographic)

  # 4. Cyan rectangle around the donut chart card (logical: 1042–1416, 242–642)
  $rx1=[single](ScX 1042); $ry1=[single](ScY 242); $rw1=[single](ScX(1416-1042)); $rh1=[single]((ScY 620)-(ScY 242))
  $rectPen = New-Object System.Drawing.Pen (C '#3FBCC9'), 4
  $g.DrawRectangle($rectPen,$rx1,$ry1,$rw1,$rh1)

  # 5. Green double-arrow line across the chart baseline (logical: x=334–998, y=605)
  $dalPen = New-Object System.Drawing.Pen (C '#3FD42B'), 3.5
  $dalPen.StartCap='Round'
  $fwdCap = New-Object System.Drawing.Drawing2D.AdjustableArrowCap 3.5,3.5,$true
  $dalPen.CustomEndCap=$fwdCap
  $dalPen.CustomStartCap=(New-Object System.Drawing.Drawing2D.AdjustableArrowCap 3.5,3.5,$true)
  $g.DrawLine($dalPen,(P (ScX 342) (ScY 608)),(P (ScX 990) (ScY 608)))

  # 6. Blue line under the "Sales overview" heading (pen tool)
  $penLine = New-Object System.Drawing.Pen (C '#2E8BFF'), 3
  $penLine.StartCap='Round'; $penLine.EndCap='Round'
  $g.DrawLine($penLine,(P (ScX 262) (ScY 68)),(P (ScX 660) (ScY 75)))

  # 7. Purple ellipse around the "Visitors" KPI card (logical: 830–1096, 110–222)
  $ellPen = New-Object System.Drawing.Pen (C '#B57CFF'), 4
  $ex=[single](ScX 830); $ey=[single](ScY 110); $ew=[single](ScX(1096-830)); $eh=[single]((ScY 222)-(ScY 110))
  $g.DrawEllipse($ellPen,$ex,$ey,$ew,$eh)

  # 8. Text annotation label "Track this!" near Visitors KPI
  $g.FillPath((Brush '#04141A' 210),(RoundRect (ScX 1100) (ScY 100) 76 22 11))
  $g.DrawString('Track this!',(Font $urbanSemi 12),(Brush '#B57CFF'),
    [single](ScX 1106),[single](ScY 104),[System.Drawing.StringFormat]::GenericTypographic)

  # 9. Star stamp on the #1042 order row (logical: x≈880, y≈759)
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

  # 10. Orange check stamp on #1041 row (logical: y≈793)
  $g.FillEllipse((Brush '#FF8C00' 200),[single]((ScX 880)-12),[single]((ScY 793)-12),24,24)
  $ckPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 3
  $ckPen.StartCap='Round'; $ckPen.EndCap='Round'; $ckPen.LineJoin='Round'
  $g.DrawLines($ckPen,[System.Drawing.PointF[]]@(
    (P ((ScX 874)) ((ScY 793)+1)),(P ((ScX 879)) ((ScY 793)+7)),(P ((ScX 888)) ((ScY 793)-5))))

  # 11. Pink heart stamp on #1040 row (logical: y≈827)
  $hcx2=[single](ScX 880); $hcy2=[single](ScY 827)
  $g.FillEllipse((Brush '#FF3FD1' 200),[single]($hcx2-5),[single]($hcy2-9),14,12)
  $g.FillEllipse((Brush '#FF3FD1' 200),[single]($hcx2+2),[single]($hcy2-9),14,12)
  $g.FillPolygon((Brush '#FF3FD1' 200),[System.Drawing.PointF[]]@(
    (P ($hcx2-5) ($hcy2-1)),(P ($hcx2+16) ($hcy2-1)),(P ($hcx2+5.5) ($hcy2+11))))

  # 12. Cross stamp on #1039 row (logical: y≈862)
  $csPen = New-Object System.Drawing.Pen (C '#E5484D' 220), 4
  $csPen.StartCap='Round'; $csPen.EndCap='Round'
  $g.DrawLine($csPen,(P ((ScX 874)) ((ScY 862)-7)),(P ((ScX 888)) ((ScY 862)+7)))
  $g.DrawLine($csPen,(P ((ScX 888)) ((ScY 862)-7)),(P ((ScX 874)) ((ScY 862)+7)))

  # Dim outside the "selected" area
  $srX=[single](ScX 248); $srY=[single](ScY 96)
  $srW=[single](ScX(1430-248)); $srH=[single]((ScY 876)-(ScY 96))
  $selRect = New-Object System.Drawing.RectangleF $srX,$srY,$srW,$srH
  $dimRegion = New-Object System.Drawing.Region (New-Object System.Drawing.RectangleF ([single]0),([single]0),([single]600),([single]400))
  $dimRegion.Exclude($selRect)
  $g.FillRegion((Brush '#000000' 100),$dimRegion)

  # Selection corner brackets (teal).
  $g.DrawRectangle((New-Object System.Drawing.Pen (C '#3FBCC9'),1.5),
    $selRect.X,$selRect.Y,$selRect.Width,$selRect.Height)
  $brPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White),3.5
  $brPen.StartCap='Round'; $brPen.EndCap='Round'; $brPen.LineJoin='Round'
  $sl=$selRect.Left; $st=$selRect.Top; $sr=$selRect.Right; $sb=$selRect.Bottom; $arm=16
  foreach ($c in @(@($sl,$st,1,1),@($sr,$st,-1,1),@($sl,$sb,1,-1),@($sr,$sb,-1,-1))) {
    $bcx=$c[0];$bcy=$c[1];$bsx=$c[2];$bsy=$c[3]
    $g.DrawLines($brPen,[System.Drawing.PointF[]]@((P $bcx ($bcy+$bsy*$arm)),(P $bcx $bcy),(P ($bcx+$bsx*$arm) $bcy)))
  }

  # Size label.
  $g.FillPath((Brush '#04141A' 220),(RoundRect (ScX 248) 10 98 20 10))
  $g.DrawString('1184 '+[char]0x00D7+' 780',(Font $urbanSemi 11),(Brush '#E2F2F6'),
    [single]((ScX 254)),[single]13,[System.Drawing.StringFormat]::GenericTypographic)

  $g.ResetClip()

  # Glass rim.
  $rim = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
    (New-Object System.Drawing.RectangleF 0,0,600,400),(C '#3FBCC9' 160),(C '#1F97B0' 35), 60
  $g.DrawPath((New-Object System.Drawing.Pen $rim,1.5),$screen)

  # ── Vertical annotation toolbar (right side, at x=540) ────────────────────
  # Buttons: move, text, draw(active), stamp, eraser, color | undo, redo, clear
  $tbX=[single]540; $tbPad=[single]5; $slot=[single]36; $divH=[single]12; $tbW=[single]46
  $tools = @('move','text','draw','stamp','eraser','color','|','undo','redo','clear')
  $tbH = $tbPad*2; foreach ($tt in $tools) { $tbH += if ($tt -eq '|'){$divH}else{$slot} }
  $tbY = [single]((400-$tbH)/2)

  # Shadow + pill body.
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
    # active = draw tool is "active" → teal highlight background
    if ($t -eq 'draw') {
      $g.FillPath((Brush '#3FBCC9' 60),(RoundRect ($tbX+4) ($iy+1) ($tbW-8) ($slot-2) 10))
    }
    $inkHex = if($t -eq 'draw'){'#1F97B0'}else{'#33444C'}
    $ink = New-Object System.Drawing.Pen (C $inkHex 210), 2.2
    $ink.StartCap='Round'; $ink.EndCap='Round'; $ink.LineJoin='Round'
    switch ($t) {
      'move'   { # arrow cursor
        $pts=[System.Drawing.PointF[]]@((P ($cx-7) ($cy-8)),(P ($cx-7) ($cy+7)),(P ($cx-2) ($cy+3)),(P ($cx+5) ($cy+9)),(P ($cx+7) ($cy+7)),(P ($cx+0) ($cy+1)),(P ($cx+4) ($cy-3)))
        $g.FillPolygon((Brush '#33444C' 200),$pts); $g.DrawPolygon($ink,$pts) }
      'text'   { $g.DrawString('T',(Font $urbanBold 21),(Brush '#33444C' 200),[single]($cx-7),[single]($cy-12),[System.Drawing.StringFormat]::GenericTypographic) }
      'draw'   { # pen diagonal
        $pPen = New-Object System.Drawing.Pen (C '#1F97B0'),2.2; $pPen.StartCap='Round';$pPen.EndCap='Round'
        $g.DrawLine($pPen,(P ($cx-7) ($cy+7)),(P ($cx+7) ($cy-7)))
        $g.FillPolygon((Brush '#1F97B0'),[System.Drawing.PointF[]]@((P ($cx+4) ($cy-10)),(P ($cx+11) ($cy-3)),(P ($cx+7) ($cy-7))))
      }
      'stamp'  { # 5-point star
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
        # trash can
        $g.DrawRectangle($ink,[single]($cx-6),[single]($cy-6),12,13)
        $g.DrawLine($ink,(P ($cx-9) ($cy-6)),(P ($cx+9) ($cy-6)))
        # (no fill needed for trash lid interior)
        $g.DrawRectangle($ink,[single]($cx-4),[single]($cy-10),8,4)
        $g.DrawLine($ink,(P ($cx-2) ($cy-4)),(P ($cx-2) ($cy+4)))
        $g.DrawLine($ink,(P ($cx+2) ($cy-4)),(P ($cx+2) ($cy+4)))
      }
    }
    $iy += $slot
  }

  $g.Restore($state)
}

# ── Tool-chip label strip ─────────────────────────────────────────────────────
# A thin row of pill chips, each naming one tool family.
function Draw-ToolChip($g,$x,$y,$label,$hex,$px) {
  $f = Font $urbanSemi $px
  $tw = TextWidth $g $label $f
  $h=[single]($px*2.0); $padX=[single]($px*0.9)
  $w=[single]($padX*2+$tw)
  $g.FillPath((Brush $hex 30),(RoundRect $x $y $w $h ($h/2)))
  $g.DrawPath((New-Object System.Drawing.Pen (C $hex 140),1.2),(RoundRect $x $y $w $h ($h/2)))
  $g.DrawString($label,$f,(Brush $hex 220),[single]($x+$padX),[single]($y+($h-$px*1.18)/2),
    [System.Drawing.StringFormat]::GenericTypographic)
  return $w
}

# ── Main canvas ──────────────────────────────────────────────────────────────
$W=1200; $H=628
$bmp = New-Object System.Drawing.Bitmap $W,$H,([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode='AntiAlias'; $g.TextRenderingHint='AntiAliasGridFit'
$g.InterpolationMode='HighQualityBicubic'; $g.PixelOffsetMode='HighQuality'

# Background.
$bg=[TBMarble]::Render($W,$H,46.0,420.0)
$g.DrawImage($bg,0,0,$W,$H); $bg.Dispose()
Draw-Stars $g $W $H ([int]($W*$H/5800)) 77
Draw-Glow $g 820 320 380 270 '#1F97B0' 85

# Logo (top-left).
Draw-Icon $g 60 44 52
Draw-Wordmark $g 130 52 30 '#FFFFFF' '#3FBCC9'

# Headline.
$hf = Font $outfitXB 54
$g.DrawString('Every annotation',$hf,(Brush '#FFFFFF'),[single]60,[single]128,[System.Drawing.StringFormat]::GenericTypographic)
$g.DrawString('tool you need.',$hf,(Brush '#3FBCC9'),[single]60,[single]192,[System.Drawing.StringFormat]::GenericTypographic)

# Sub-copy.
$g.DrawString(
  'Pen, highlighter, arrows, shapes, stamps, text',(Font $urbanMed 20),(Brush '#B5D3DA'),
  (New-Object System.Drawing.RectangleF 62,268,430,50))
$g.DrawString(
  'and a colour picker — all in one key press.',(Font $urbanMed 20),(Brush '#B5D3DA'),
  (New-Object System.Drawing.RectangleF 62,296,430,50))

# Tool chips (two rows of 4).
$toolChips = @(
  @('Pen',        '#2E8BFF'),
  @('Highlighter','#FFD700'),
  @('Arrow',      '#E5484D'),
  @('Shapes',     '#3FBCC9'),
  @('Stamps',     '#FF3FD1'),
  @('Text',       '#B57CFF'),
  @('Eraser',     '#9CC1CA'),
  @('Colors × 15','#FF8C00')
)
$chipPx=14; $chipGap=8
$row1chips = $toolChips[0..3]; $row2chips = $toolChips[4..7]
$cx=62
foreach ($tc in $row1chips) { $cw=(Draw-ToolChip $g $cx 362 $tc[0] $tc[1] $chipPx); $cx+=$cw+$chipGap }
$cx=62
foreach ($tc in $row2chips) { $cw=(Draw-ToolChip $g $cx 395 $tc[0] $tc[1] $chipPx); $cx+=$cw+$chipGap }

# CTA button.
$bf = Font $urbanBold 20
$btnTw = TextWidth $g 'Download free' $bf
$btnW = $btnTw + 20*3.4; $btnH = 20*2.6
Draw-Glow $g (62+$btnW/2) (456+$btnH/2) ($btnW*0.7) ($btnH*1.3) '#3FBCC9' 70
$btnFill = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
  (New-Object System.Drawing.RectangleF ([single]62),([single]456),([single]$btnW),([single]$btnH)),
  (C '#3FBCC9'),(C '#1F97B0'),0
$g.FillPath($btnFill,(RoundRect 62 456 $btnW $btnH ($btnH/2)))
$g.DrawString('Download free',$bf,(Brush '#04141A'),[single](62+20*1.7),[single](456+($btnH-20*1.22)/2),
  [System.Drawing.StringFormat]::GenericTypographic)
$siteX = 62+$btnW+18
$g.DrawString('alienwavegroup.com',(Font $urbanSemi 18),(Brush '#9CC1CA'),[single]$siteX,[single]472,
  [System.Drawing.StringFormat]::GenericTypographic)

# Divider line between copy and mockup.
$g.FillRectangle((Brush '#3FBCC9' 30),530,80,1,480)

# Annotated mockup (right side).
Draw-AnnotatedMockup $g 538 64 630

$g.Dispose()
New-Item -ItemType Directory -Force $Out | Out-Null
$bmp.Save("$Out\banner-tools-1200x628.png",[System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose(); $scene.Dispose(); $appIcon.Dispose()
"Saved: $Out\banner-tools-1200x628.png"
