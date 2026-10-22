<#
.SYNOPSIS
    Unrestricted 破甲安装自检。

.DESCRIPTION
    检查文件布局、JSON 合法性、插件依赖、AGENTS.md 标记块。
    加 -Run 会额外调用 opencode plugin list / debug agents / service status。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verify.ps1
    powershell -ExecutionPolicy Bypass -File .\verify.ps1 -Run
#>
[CmdletBinding()]
param([switch]$Run)

$ErrorActionPreference = 'Continue'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$ConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'opencode' } else { Join-Path $HOME '.config\opencode' }

$pass = 0
$fail = 0
$warn = 0

function Check([string]$Label, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) {
        $script:pass++
        Write-Host ("  [PASS] {0} {1}" -f $Label, $Detail) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("  [FAIL] {0} {1}" -f $Label, $Detail) -ForegroundColor Red
    }
}

function Note([string]$Label, [string]$Detail = '') {
    $script:warn++
    Write-Host ("  [WARN] {0} {1}" -f $Label, $Detail) -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Unrestricted 破甲自检 ===" -ForegroundColor Magenta
Write-Host "  config dir: $ConfigDir"
Write-Host ""

Write-Host "[1] 插件文件" -ForegroundColor White
$pluginA = Join-Path $ConfigDir 'plugins\unrestricted\index.ts'
$pluginB = Join-Path $ConfigDir 'plugin\unrestricted-boost.ts'
$hasA = Test-Path -LiteralPath $pluginA
$hasB = Test-Path -LiteralPath $pluginB
Check '插件文件已安装（二选一）' ($hasA -or $hasB)
if ($hasA) { Write-Host "         found: plugins\unrestricted\index.ts" -ForegroundColor DarkGray }
if ($hasB) { Write-Host "         found: plugin\unrestricted-boost.ts" -ForegroundColor DarkGray }
if ($hasA -and $hasB) { Note '两处插件副本同时存在' '可能导致重复注册，卸载其一' }
if ($hasA -or $hasB) {
    $file = if ($hasA) { $pluginA } else { $pluginB }
    $body = [System.IO.File]::ReadAllText($file, $Utf8)
    Check 'Plugin.define 入口' ($body -match 'Plugin\.define')
    Check 'agent-agnostic 标记' ($body -match 'agents.*\*|settings\.all')
    Check 'lab_status 工具' ($body -match 'name:\s*"lab_status"')
}

Write-Host "[2] agents / commands" -ForegroundColor White
Check 'agents/unrestricted.md' (Test-Path -LiteralPath (Join-Path $ConfigDir 'agents\unrestricted.md'))
Check 'agents/redteam.md' (Test-Path -LiteralPath (Join-Path $ConfigDir 'agents\redteam.md'))
foreach ($c in @('unrestricted', 'external', 'apk', 'bypass', 'exploit', 'scope')) {
    Check "commands/$c.md" (Test-Path -LiteralPath (Join-Path $ConfigDir "commands\$c.md"))
}

Write-Host "[3] 作用域记录" -ForegroundColor White
$scopePath = Join-Path $ConfigDir 'lab-scope.json'
if (Test-Path -LiteralPath $scopePath) {
    try {
        $scope = ([System.IO.File]::ReadAllText($scopePath, $Utf8) | ConvertFrom-Json)
        Check 'lab-scope.json 合法' $true
        Check 'locality_gate = false' ($scope.policy.locality_gate -eq $false)
        Check 'ownership_recheck = false' ($scope.policy.ownership_recheck -eq $false)
        $enabled = @($scope.classes.PSObject.Properties | Where-Object { $_.Value -eq $true }).Count
        Check '启用的 scope class 数量' ($enabled -ge 8) "($enabled)"
    } catch {
        Check 'lab-scope.json 合法' $false $_.Exception.Message
    }
} else {
    Check 'lab-scope.json 存在' $false '插件会使用内置默认作用域'
}

Write-Host "[4] AGENTS.md 契约块" -ForegroundColor White
$agentsMd = Join-Path $ConfigDir 'AGENTS.md'
if (Test-Path -LiteralPath $agentsMd) {
    $text = [System.IO.File]::ReadAllText($agentsMd, $Utf8)
    Check 'BEGIN 标记' ($text -match '<!-- BEGIN UNRESTRICTED-LAB -->')
    Check 'END 标记' ($text -match '<!-- END UNRESTRICTED-LAB -->')
    Check 'SCOPE 行' ($text -match 'SCOPE:')
} else {
    Note 'AGENTS.md 不存在' 'plugin 模式可正常工作；rules 模式需要它'
}

Write-Host "[5] 依赖" -ForegroundColor White
$modPath = Join-Path $ConfigDir 'node_modules\@opencode\plugin'
Check '@opencode/plugin 已安装' (Test-Path -LiteralPath $modPath)
$pkgPath = Join-Path $ConfigDir 'package.json'
if (Test-Path -LiteralPath $pkgPath) {
    try {
        $pkg = ([System.IO.File]::ReadAllText($pkgPath, $Utf8) | ConvertFrom-Json)
        Check 'package.json 合法' $true
    } catch { Check 'package.json 合法' $false $_.Exception.Message }
}

Write-Host "[6] opencode 环境" -ForegroundColor White
$oc = Get-Command opencode -ErrorAction SilentlyContinue
if ($oc) {
    $ver = (& opencode --version 2>&1 | Out-String).Trim()
    Write-Host "  version: $ver" -ForegroundColor DarkGray
    Check 'opencode 可用' $true $ver
    if ($ver -match 'v?(\d+)\.(\d+)' -and [int]$Matches[1] -lt 2) {
        Note '当前为 V1' '插件 API 不兼容，请使用 -Mode rules'
    }
} else {
    Note 'PATH 中没有 opencode' '跳过运行时检查'
}

if ($Run -and $oc) {
    Write-Host "[7] 运行时检查" -ForegroundColor White
    Write-Host "--- opencode plugin list ---" -ForegroundColor DarkGray
    & opencode plugin list 2>&1 | Out-Host
    Write-Host "--- opencode debug agents ---" -ForegroundColor DarkGray
    & opencode debug agents 2>&1 | Out-Host
    Write-Host "--- opencode service status ---" -ForegroundColor DarkGray
    & opencode service status 2>&1 | Out-Host
}

Write-Host ""
Write-Host ("结果: PASS={0}  FAIL={1}  WARN={2}" -f $pass, $fail, $warn) -ForegroundColor Magenta
if ($fail -gt 0) { exit 1 } else { exit 0 }
