param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
$workerRoot = Join-Path $PSScriptRoot 'agent_dispatch'
$resolvedDestination = [System.IO.Path]::GetFullPath($Destination)
$runtimeDestination = Join-Path $resolvedDestination 'runtime'

function Invoke-NpmCommand {
    param([string[]]$Arguments)

    & npm.cmd @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "npm $($Arguments -join ' ') 失败，退出码 $LASTEXITCODE"
    }
}

Write-Host '构建 Agent Worker…'
Push-Location $workerRoot
try {
    Invoke-NpmCommand @('ci')
    Invoke-NpmCommand @('run', 'build')
    Invoke-NpmCommand @('prune', '--omit=dev')
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Path $resolvedDestination -Force | Out-Null
New-Item -ItemType Directory -Path $runtimeDestination -Force | Out-Null

Copy-Item (Join-Path $workerRoot 'package.json') $resolvedDestination
Copy-Item (Join-Path $workerRoot 'package-lock.json') $resolvedDestination
Copy-Item (Join-Path $workerRoot 'dist') $resolvedDestination -Recurse
Copy-Item (Join-Path $workerRoot 'node_modules') $resolvedDestination -Recurse

$nodeExecutable = (Get-Command node.exe -ErrorAction Stop).Source
Copy-Item $nodeExecutable (Join-Path $runtimeDestination 'node.exe')

$cliPath = Join-Path $resolvedDestination 'dist\cli.js'
$sdkPath = Join-Path $resolvedDestination 'node_modules\@cursor\sdk'
$codexPath = Join-Path $resolvedDestination 'node_modules\@openai\codex\bin\codex.js'
$bundledNode = Join-Path $runtimeDestination 'node.exe'
if (!(Test-Path $cliPath) -or !(Test-Path $sdkPath) -or !(Test-Path $codexPath) -or !(Test-Path $bundledNode)) {
    throw 'Agent Worker 发布内容不完整'
}

Write-Host "Agent Worker 已打包到：$resolvedDestination"
