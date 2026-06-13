# Using Visual Studio 2022 Developer PowerShell
# or using e.g. "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\makeappx.exe"

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$makeAppx = Get-Command MakeAppx.exe -ErrorAction SilentlyContinue
if (-not $makeAppx) {
    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    $makeAppx = Get-ChildItem -Path $kitsRoot -Recurse -Filter "makeappx.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $makeAppx) {
        throw "MakeAppx.exe not found. Install the Windows 10/11 SDK."
    }
    $makeAppxPath = $makeAppx.FullName
} else {
    $makeAppxPath = $makeAppx.Source
}

$output = Join-Path $repoRoot "app\windows\localsend_msix_helper.msix"
$msixDir = Join-Path $repoRoot "msix"

& $makeAppxPath pack /o /d $msixDir /nv /p $output
