Write-Host "== java 进程 =="
$j = Get-Process -Name java -ErrorAction SilentlyContinue
if ($j) { $j | Select-Object CPU, WorkingSet, StartTime | Format-List } else { Write-Host "无 java 进程" }

Write-Host "== gradle 缓存最近更新 =="
$cacheDir = Join-Path $env:USERPROFILE ".gradle\caches"
if (Test-Path $cacheDir) {
    Get-ChildItem $cacheDir | Sort-Object LastWriteTime -Descending | Select-Object -First 8 Name, LastWriteTime | Format-Table -AutoSize
} else { Write-Host "无 caches 目录" }

Write-Host "== wrapper dists 最近更新 =="
$wrapDir = Join-Path $env:USERPROFILE ".gradle\wrapper\dists"
if (Test-Path $wrapDir) {
    Get-ChildItem $wrapDir -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 5 FullName, LastWriteTime | Format-Table -AutoSize
} else { Write-Host "无 wrapper dists 目录" }

Write-Host "== 当前时间 =="
Get-Date
