Write-Host "== time =="
Get-Date

Write-Host "== java process =="
$j = Get-Process -Name java -ErrorAction SilentlyContinue
if ($j) { $j | Select-Object CPU, WorkingSet, StartTime | Format-List } else { Write-Host "no java process" }

Write-Host "== adb devices =="
$adb = "C:\Android\Sdk\platform-tools\adb.exe"
if (Test-Path $adb) { & $adb devices } else { Write-Host "adb missing" }

Write-Host "== gradle 7.5 download =="
$wrapBase = Join-Path $env:USERPROFILE ".gradle\wrapper\dists\gradle-7.5-all"
if (Test-Path $wrapBase) {
    Get-ChildItem $wrapBase -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 6 FullName, Length, LastWriteTime | Format-Table -AutoSize
} else { Write-Host "gradle-7.5-all dir not created yet" }

Write-Host "== gradle caches recent =="
$cacheDir = Join-Path $env:USERPROFILE ".gradle\caches"
if (Test-Path $cacheDir) {
    Get-ChildItem $cacheDir | Sort-Object LastWriteTime -Descending | Select-Object -First 6 Name, LastWriteTime | Format-Table -AutoSize
} else { Write-Host "no caches" }

Write-Host "== project build dir =="
$bdir = "d:\code\showlocation\build"
if (Test-Path $bdir) {
    Get-ChildItem $bdir | Sort-Object LastWriteTime -Descending | Select-Object -First 6 Name, LastWriteTime | Format-Table -AutoSize
} else { Write-Host "no build dir" }
