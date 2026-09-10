# Собирает композиции "ласточка в колесе" из исходников в assets/src.
# Запуск:  powershell -ExecutionPolicy Bypass -File tools\make-wheel-logo.ps1
# Требует только Windows PowerShell + System.Drawing (Python/ImageMagick/Node на машине нет).

$root = Split-Path -Parent $PSScriptRoot
Add-Type -TypeDefinition (Get-Content "$PSScriptRoot\imgtool.cs" -Raw) -ReferencedAssemblies 'System.Drawing' -ErrorAction Stop

$wheel = "$root\assets\src\wheel-source.png"
$logo  = "$root\assets\src\swallow-source.jpg"
$out   = "$root\assets\img"

# --- измеренная геометрия (пересчитывается автоматически, значения для справки) ---
# Обод колеса:  центр (576, 356), внешний R = 226, внутренний R = 187, полоса 39 px
# Кольцо знака: центр (256, 248), внешний R = 149, внутренний R = 131, штрих 18 px
$RIM_CX = 576; $RIM_CY = 356; $RIM_OUTER = 226; $RIM_MID = 206.5; $RIM_INNER = 185

$m = [ImgTool]::MeasureRing($logo, 90)   # -> cx, cy, outerR, innerR, midR, углов найдено
"кольцо знака: центр=({0},{1}) outerR={2} innerR={3} midR={4} углов={5}" -f $m[0],$m[1],$m[2],$m[3],$m[4],$m[5]

# Вариант 2: внешний край кольца знака = внешний край обода
[ImgTool]::MakeAnchored($wheel, $logo, "$out\wheel-swallow-badge.jpg",
    $RIM_CX, $RIM_CY, $RIM_OUTER, $m[0], $m[1], $m[2], 1.0, 0.55, $false)

# Вариант 2-mid, принят: совмещение по средней линии обода
[ImgTool]::MakeAnchored($wheel, $logo, "$out\wheel-swallow-badge-mid.jpg",
    $RIM_CX, $RIM_CY, $RIM_MID, $m[0], $m[1], $m[4], 1.0, 0.55, $false)

# Вариант 1: только птица, обод колеса работает кольцом логотипа
[ImgTool]::MakeVariant($wheel, $logo, "$out\wheel-swallow.jpg",
    $RIM_CX, $RIM_CY, $RIM_INNER, 0, 0.84, 1.0, 0.55, 4, 0, $false)

# Прозрачные PNG знака отдельно
[ImgTool]::ExportLogo($logo, "$out\swallow-bird.png", 90, 0)
[ImgTool]::ExportLogo($logo, "$out\swallow-mark.png", 90, 1)

# --- вырезка: колесо с дымом без асфальта и кузова ---
# Работаем от PNG без потерь, иначе JPEG-артефакты ломают замер фактуры.
$mid = "$root\assets\src\mid-lossless.png"
[ImgTool]::MakeAnchored($wheel, $logo, $mid,
    $RIM_CX, $RIM_CY, $RIM_MID, $m[0], $m[1], $m[4], 1.0, 0.55, $true)

# Параметры: rHard/feather — покрышка; яркость 125..182 — дым против кузова;
# std 4..11 — гладкий дым против зернистого асфальта; (R+B)/2-G 6..12 — пурпур кузова;
# радиальное затухание 420+170; горизонтальный срез 670+70; порог 0.10; окно 11x11; блюр 2.
[ImgTool]::Cutout2($mid, "$out\wheel-swallow-cutout-full.png", "$root\tools\cutout-check.jpg",
    $RIM_CX, $RIM_CY, 252, 12, 125, 182, 4, 11, 6, 12, 420, 170, 670, 70, 0.10, 5, 2)
[ImgTool]::Trim("$out\wheel-swallow-cutout-full.png", "$out\wheel-swallow-cutout.png", 3, 8)
[ImgTool]::OverBg("$out\wheel-swallow-cutout.png", "$root\tools\cutout-on-grey.jpg", 120, 120, 120)

# JPG-версии обеих вырезок. JPEG прозрачность не хранит, поэтому фон запекается
# в цвет сайта --ink #0a0a0b (10,10,11) из assets/css/style.css.
[ImgTool]::OverBg("$out\wheel-swallow-cutout.png",      "$out\wheel-swallow-cutout.jpg",      10, 10, 11)
[ImgTool]::OverBg("$out\wheel-swallow-cutout-full.png", "$out\wheel-swallow-cutout-full.jpg", 10, 10, 11)

# Контрольная картинка с найденными окружностями обода
[ImgTool]::DebugCircles($wheel, "$root\tools\rim-check.jpg", $RIM_CX, $RIM_CY, @(187, 226, 165))
"готово"
