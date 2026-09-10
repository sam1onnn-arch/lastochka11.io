# Готовит знак для главного экрана.
#
# На странице знак накладывается режимом screen: чёрное становится прозрачным.
# Поэтому фон обязан быть ИСТИННО чёрным — обычного JPEG мало, его шум в тенях
# (значения 8…16 вместо 0) виден на странице как прямоугольная подложка.
# Здесь прозрачный PNG кладётся на чистый чёрный, тени подрезаются до нуля,
# и только потом кадр уходит в JPEG с высоким качеством.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$img    = 'C:\Users\PC\Desktop\ии\For Andrey\assets\img'
$source = "$img\wheel-swallow-cutout.png"   # уже обрезан по содержимому
$out    = "$img\hero-mark.jpg"

$targetW  = 820
$floor    = 30    # всё темнее — в ноль
$knee     = 52    # до этого значения тени плавно растягиваются

$src = [System.Drawing.Image]::FromFile($source)
$w = $targetW
$h = [int][Math]::Round($src.Height * ([double]$w / $src.Width))

$canvas = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.Clear([System.Drawing.Color]::Black)
$g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $w, $h), 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose(); $src.Dispose()

# Подрезаем тени по пикселям
$rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
$data = $canvas.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, $canvas.PixelFormat)
$bytes = New-Object byte[] ($data.Stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

# Таблица перевода: 0..floor -> 0, floor..knee -> плавный подъём, дальше без изменений
$lut = New-Object byte[] 256
for ($v = 0; $v -lt 256; $v++) {
  if ($v -le $floor) { $lut[$v] = 0 }
  elseif ($v -lt $knee) {
    $t = ($v - $floor) / [double]($knee - $floor)
    $lut[$v] = [byte][Math]::Round($knee * $t * $t)
  }
  else { $lut[$v] = [byte]$v }
}

for ($y = 0; $y -lt $h; $y++) {
  $row = $y * $data.Stride
  for ($x = 0; $x -lt $w; $x++) {
    $i = $row + $x * 3
    $b = $bytes[$i]; $gr = $bytes[$i + 1]; $r = $bytes[$i + 2]
    # порог по самому яркому каналу, чтобы не перекрасить цветные пиксели знака
    if ([Math]::Max($r, [Math]::Max($gr, $b)) -le $floor) {
      $bytes[$i] = 0; $bytes[$i + 1] = 0; $bytes[$i + 2] = 0
    } else {
      $bytes[$i] = $lut[$b]; $bytes[$i + 1] = $lut[$gr]; $bytes[$i + 2] = $lut[$r]
    }
  }
}

[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
$canvas.UnlockBits($data)

$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 94L
$canvas.Save($out, $codec, $ep)
$canvas.Dispose()

"hero-mark.jpg  {0}x{1}  {2} KB" -f $w, $h, [math]::Round((Get-Item $out).Length / 1KB)
