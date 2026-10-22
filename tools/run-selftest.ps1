<#
.SYNOPSIS
    unrestricted-boost 插件逻辑自检（不启动 OpenCode）。

.DESCRIPTION
    在临时目录里搭一个假的 @opencode/plugin 模块，用 mock ctx 直接跑插件的 setup，
    验证：任意 agent 注入、幂等、ask→allow、prompt 改写、lab_status、白名单模式。

    需要 Node 22.6+（--experimental-strip-types）。不联网、不改任何配置。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\run-selftest.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Root = Split-Path -Parent $PSScriptRoot
$PluginSrc = Join-Path $Root 'payload\plugin\unrestricted-boost.ts'
$TestSrc = Join-Path $PSScriptRoot 'selftest.mjs'
$ScopeSrc = Join-Path $Root 'payload\lab-scope.json'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw '找不到 node，无法自检' }

$version = (& node --version).Trim()
Write-Host "node $version" -ForegroundColor DarkGray

$tmp = Join-Path $env:TEMP ("unrestricted-selftest-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    Copy-Item -LiteralPath $PluginSrc -Destination (Join-Path $tmp 'plugin.ts') -Force
    Copy-Item -LiteralPath $TestSrc -Destination (Join-Path $tmp 'selftest.mjs') -Force

    $mockDir = Join-Path $tmp 'node_modules\@opencode\plugin'
    New-Item -ItemType Directory -Force -Path $mockDir | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $mockDir 'package.json'),
        '{"name":"@opencode/plugin","version":"0.0.0","type":"module","main":"index.mjs","exports":"./index.mjs"}',
        $Utf8
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $mockDir 'index.mjs'),
        "export const Plugin = { define: (definition) => definition }`n",
        $Utf8
    )

    $old = $env:LAB_SCOPE_FILE
    $env:LAB_SCOPE_FILE = $ScopeSrc

    Push-Location $tmp
    try {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & node --no-warnings --experimental-strip-types selftest.mjs 2>&1 | Out-Host
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
    } finally {
        Pop-Location
        $env:LAB_SCOPE_FILE = $old
    }

    if ($code -ne 0) {
        Write-Host "`n自检失败（exit $code）" -ForegroundColor Red
        exit $code
    }
    Write-Host "`n插件逻辑自检通过" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
