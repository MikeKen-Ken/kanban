param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
$workerRoot = Join-Path $PSScriptRoot 'agent_dispatch'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$nodeVersionFile = Join-Path $repositoryRoot '.node-version'
$resolvedDestination = [System.IO.Path]::GetFullPath($Destination)
$runtimeDestination = Join-Path $resolvedDestination 'runtime'
$nodeExecutable = (Get-Command node.exe -ErrorAction Stop).Source
$expectedNodeVersion = (Get-Content -LiteralPath $nodeVersionFile -Raw).Trim()
$actualNodeVersion = (& $nodeExecutable --version).Trim().TrimStart('v')
if ($LASTEXITCODE -ne 0 -or $actualNodeVersion -ne $expectedNodeVersion) {
    throw "Agent Worker 要求 Node.js $expectedNodeVersion，当前为 $actualNodeVersion"
}

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

Copy-Item $nodeExecutable (Join-Path $runtimeDestination 'node.exe')

$cursorSdkPackage = Get-Content -LiteralPath (Join-Path $workerRoot 'node_modules\@cursor\sdk\package.json') -Raw | ConvertFrom-Json
$workerManifest = @{
    nodeVersion = $expectedNodeVersion
    cursorSdkVersion = $cursorSdkPackage.version
} | ConvertTo-Json
Set-Content -LiteralPath (Join-Path $resolvedDestination 'worker_manifest.json') -Value $workerManifest -Encoding utf8

$cliPath = Join-Path $resolvedDestination 'dist\cli.js'
$sdkPath = Join-Path $resolvedDestination 'node_modules\@cursor\sdk'
$mcpClientPath = Join-Path $resolvedDestination 'node_modules\@modelcontextprotocol\client'
$codexPath = Join-Path $resolvedDestination 'node_modules\@openai\codex\bin\codex.js'
$bundledNode = Join-Path $runtimeDestination 'node.exe'
if (!(Test-Path $cliPath) -or !(Test-Path $sdkPath) -or !(Test-Path $mcpClientPath) -or !(Test-Path $codexPath) -or !(Test-Path $bundledNode)) {
    throw 'Agent Worker 发布内容不完整'
}

$treeSitterBinding = Join-Path $resolvedDestination 'node_modules\@cursor\sdk-win32-x64\vendor\tree-sitter\binding.node'
$treeSitterBashBinding = Join-Path $resolvedDestination 'node_modules\@cursor\sdk-win32-x64\vendor\tree-sitter-bash\binding.node'
foreach ($binding in @($treeSitterBinding, $treeSitterBashBinding)) {
    if (!(Test-Path -LiteralPath $binding)) {
        throw "Cursor SDK 原生模块缺失：$binding"
    }
    & $bundledNode -e 'require(process.argv[1])' $binding
    if ($LASTEXITCODE -ne 0) {
        throw "Cursor SDK 原生模块与 Node.js $expectedNodeVersion 不兼容：$binding（退出码 $LASTEXITCODE）"
    }
}

Write-Host "便携 Node.js $expectedNodeVersion 与 Cursor SDK 原生模块校验通过"

Write-Host "Agent Worker 已打包到：$resolvedDestination"
