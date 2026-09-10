$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$imgDir = 'C:\Users\PC\Desktop\ии\For Andrey\assets\img'

function Convert-Image {
  param([string]$InPath, [string]$OutPath, [int]$TargetWidth, [long]$Quality = 82)

  if (-not (Test-Path -LiteralPath $InPath)) { throw "not found: $InPath" }

  $original = [System.Drawing.Image]::FromFile($InPath)
  $ow = $original.Width
  $oh = $original.Height
  if ($ow -le 0) { throw "bad width for $InPath" }

  $nw = $TargetWidth
  $nh = [int][Math]::Round($oh * ([double]$nw / [double]$ow))

  $bmp = New-Object System.Drawing.Bitmap $nw, $nh
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

  $rect = New-Object System.Drawing.Rectangle 0, 0, $nw, $nh
  $g.DrawImage($original, $rect, 0, 0, $ow, $oh, [System.Drawing.GraphicsUnit]::Pixel)

  $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
  $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $Quality
  $bmp.Save($OutPath, $codec, $ep)

  $g.Dispose(); $bmp.Dispose(); $original.Dispose()
  "{0,-20} {1}x{2} -> {3}x{4}  {5} KB" -f (Split-Path $OutPath -Leaf), $ow, $oh, $nw, $nh, [math]::Round((Get-Item -LiteralPath $OutPath).Length / 1KB)
}

$cand = 'C:\Users\PC\AppData\Local\Temp\claude\C--Users-PC-Desktop----For-Andrey\9d7aea28-9885-4262-9548-666df4f3d0b4\scratchpad\cand'
Convert-Image -InPath "$cand\ch4-a-key-merc.jpg"  -OutPath "$imgDir\work-keys.jpg" -TargetWidth 1400 -Quality 82
Convert-Image -InPath "$cand\ch5-c-toolchest.jpg" -OutPath "$imgDir\work-box.jpg"  -TargetWidth 1600 -Quality 82