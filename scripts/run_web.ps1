# 固定端口启动 Flutter Web（Chrome 调试）
$WebPort = 7358

$env:Path = "C:\src\flutter\bin;" + $env:Path
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "启动看板 Web 版: http://localhost:$WebPort" -ForegroundColor Cyan
flutter run -d chrome --web-port=$WebPort
