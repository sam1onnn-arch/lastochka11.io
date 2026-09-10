$ErrorActionPreference = 'Stop'
$root = 'C:\Users\PC\Desktop\ии\For Andrey'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$out  = Join-Path $dist 'lastochka11.html'

$html = [IO.File]::ReadAllText("$root\index.html", [Text.Encoding]::UTF8)
$css  = [IO.File]::ReadAllText("$root\assets\css\style.css", [Text.Encoding]::UTF8)
$js   = [IO.File]::ReadAllText("$root\assets\js\main.js", [Text.Encoding]::UTF8)
function Get-DataUri([string]$Path) {
  'data:image/jpeg;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
}

$b64      = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$root\assets\img\hero-master.jpg"))
$uriBal   = Get-DataUri "$root\assets\img\work-balance.jpg"
$uriGbc   = Get-DataUri "$root\assets\img\work-gbc.jpg"
$uriAkpp  = Get-DataUri "$root\assets\img\work-akpp.jpg"
$uriKeys  = Get-DataUri "$root\assets\img\work-keys.jpg"
$uriBox   = Get-DataUri "$root\assets\img\work-box.jpg"

# фоны глав: в артефакте нет папки assets, поэтому пути становятся data URI
$css = $css.Replace('../img/work-balance.jpg', $uriBal)
$css = $css.Replace('../img/work-gbc.jpg',     $uriGbc)
$css = $css.Replace('../img/work-akpp.jpg',    $uriAkpp)
$css = $css.Replace('../img/work-keys.jpg',    $uriKeys)
$css = $css.Replace('../img/work-box.jpg',     $uriBox)

# содержимое <body>
$m = [regex]::Match($html, '(?s)<body>(.*)</body>')
if (-not $m.Success) { throw 'body not found' }
$body = $m.Groups[1].Value

# внешний скрипт уедет инлайном ниже
$body = $body -replace '<script src="assets/js/main\.js"></script>', ''
# фото — в data URI
$body = $body.Replace('assets/img/hero-master.jpg', "data:image/jpeg;base64,$b64")
# логотип заставки — PNG с прозрачностью, поэтому свой тип
$logoPng = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$root\assets\img\logo-full.png"))
$body = $body.Replace('assets/img/logo-full.png', "data:image/png;base64,$logoPng")

# страховка: ни одной ссылки на assets остаться не должно, иначе картинка
# молча не загрузится — в артефакте этой папки нет
$left = [regex]::Matches($body + $css, 'assets/img/[^"''\)\s]+') | ForEach-Object { $_.Value } | Sort-Object -Unique
if ($left) { throw "в сборке остались ссылки на assets: $($left -join ', ')" }

$tpl = @'
<title>ЛаСТОчка11</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Unbounded:wght@200;300;400&family=Manrope:wght@200;300;400;500;600&display=swap" rel="stylesheet">
<style>
__CSS__
</style>

__BODY__

<script>
__JS__
</script>
<script>
/* страховка: если что-то не отработало, показываем всё через 2,5 с */
setTimeout(function () {
  var p = document.getElementById('preloader');
  if (p) { p.classList.add('is-done'); }
  var h = document.getElementById('hero');
  if (h) { h.classList.add('is-in'); }
  document.querySelectorAll('.reveal:not(.is-in)').forEach(function (el) {
    var r = el.getBoundingClientRect();
    if (r.top < window.innerHeight * 1.4) el.classList.add('is-in');
  });
}, 2500);
</script>
'@

$page = $tpl.Replace('__CSS__', $css).Replace('__BODY__', $body).Replace('__JS__', $js)
[IO.File]::WriteAllText($out, $page, (New-Object Text.UTF8Encoding $false))

"built: {0} KB" -f [math]::Round((Get-Item $out).Length / 1KB)
