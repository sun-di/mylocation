$env:PATH = "C:\src\flutter\bin;" + $env:PATH
$env:ANDROID_SDK_ROOT = "C:\Android\Sdk"
Set-Location "d:\code\showlocation"
# 高德 Key 注入文件（不入库）。不存在则自动从模板复制一份，提示你填 Key。
$keyFile = "keys\dart_define.json"
$keyTemplate = "keys\dart_define.example.json"
if (-not (Test-Path $keyFile)) {
    if (Test-Path $keyTemplate) {
        Copy-Item $keyTemplate $keyFile
        Write-Host "已自动生成 $keyFile" -ForegroundColor Green
        Write-Host "请用编辑器打开它，填入你的高德 Key（AMAP_ANDROID_KEY / AMAP_IOS_KEY / AMAP_WEB_KEY）"
        Write-Host "填好后重新双击运行本脚本即可。"
    } else {
        Write-Host "[错误] 未找到模板 $keyTemplate" -ForegroundColor Red
    }
    Read-Host "按回车退出"
    exit 1
}

Write-Host "开始 flutter run (AGP 8.11.1 / Gradle 8.14.3 / Kotlin 2.2.20) ..."
flutter run --dart-define-from-file=keys/dart_define.json
Write-Host "=== flutter run 结束, exit: $LASTEXITCODE ==="
