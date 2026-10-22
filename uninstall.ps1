<#
.SYNOPSIS
    Unrestricted 破甲卸载器。

.DESCRIPTION
    默认只做三件事（保留 agents / commands / lab-scope.json）：
      1. 移除 unrestricted-boost 插件（含 plugins\unrestricted 目录）
      2. 从 opencode.json 的 plugins 数组移除 unrestricted 条目
      3. 从全局 AGENTS.md 移除 UNRESTRICTED-LAB 标记块

.PARAMETER RemoveFiles
    额外卸载 agents\unrestricted.md、agents\redteam.md、commands\*.md；
    若存在 kit 备份则从最新备份恢复。

.PARAMETER PurgeScope
    删除 lab-scope.json（审计记录）。

.PARAMETER RestoreConfig
    从最新 kit 备份恢复 opencode.json（会覆盖安装后的配置改动）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveFiles -PurgeScope
#>
[CmdletBinding()]
param(
    [switch]$RemoveFiles,
    [switch]$PurgeScope,
    [switch]$RestoreConfig,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$ConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'opencode' } else { Join-Path $HOME '.config\opencode' }

function Write-Step([string]$Text) { Write-Host "  -> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  OK $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host "  !! $Text" -ForegroundColor Yellow }

function Remove-Safe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($DryRun) { Write-Step "remove $Path"; return }
    Remove-Item -LiteralPath $Path -Recurse -Force
    Write-Step "removed $Path"
}

Write-Host ""
Write-Host "=== Unrestricted 破甲卸载器 ===" -ForegroundColor Magenta
Write-Host "  config dir: $ConfigDir"
if ($DryRun) { Write-Host "  DRY RUN   : 不修改任何文件" -ForegroundColor Yellow }
Write-Host ""

$latestBackup = $null
$backupRoot = Join-Path $ConfigDir '_backup'
if (Test-Path -LiteralPath $backupRoot) {
    $latestBackup = Get-ChildItem -LiteralPath $backupRoot -Directory -Filter 'unrestricted-kit-*' |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($latestBackup) { Write-Host "  最新备份: $($latestBackup.FullName)" -ForegroundColor DarkGray }
    else { Write-Warn2 "没有找到 kit 备份，卸载将只做删除" }
}

# ── 1. 插件 ─────────────────────────────────────────────────────────────────
Write-Host "[1/4] 移除插件" -ForegroundColor White

# plugins\unrestricted 一定是 kit 装的目录
Remove-Safe (Join-Path $ConfigDir 'plugins\unrestricted')

# plugin\unrestricted-boost.ts：有备份就恢复安装前版本，没有就删除
$pluginDest = Join-Path $ConfigDir 'plugin\unrestricted-boost.ts'
$pluginBackup = if ($latestBackup) { Join-Path $latestBackup.FullName 'plugin\unrestricted-boost.ts' } else { $null }
if ($pluginBackup -and (Test-Path -LiteralPath $pluginBackup)) {
    if ($DryRun) { Write-Step "restore plugin\unrestricted-boost.ts" }
    else {
        Copy-Item -LiteralPath $pluginBackup -Destination $pluginDest -Force
        Write-Step "restored plugin\unrestricted-boost.ts"
    }
} else {
    Remove-Safe $pluginDest
}

# 处理安装时被改名的旧副本：目标已存在则清理，不存在则恢复
foreach ($dir in @('plugin', 'plugins\unrestricted')) {
    $full = Join-Path $ConfigDir $dir
    if (-not (Test-Path -LiteralPath $full)) { continue }
    Get-ChildItem -LiteralPath $full -Filter '*.disabled-*' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $original = $_.FullName -replace '\.disabled-\d{8}-\d{6}$', ''
            if (Test-Path -LiteralPath $original) {
                Remove-Safe $_.FullName
            } elseif ($DryRun) {
                Write-Step "restore $original"
            } else {
                Move-Item -LiteralPath $_.FullName -Destination $original -Force
                Write-Step "restored $original"
            }
        }
}

# ── 2. opencode.json 中的注册项 ─────────────────────────────────────────────
Write-Host "[2/4] 清理 opencode.json" -ForegroundColor White
$cfgPath = Join-Path $ConfigDir 'opencode.json'
if (-not (Test-Path -LiteralPath $cfgPath)) { $cfgPath = Join-Path $ConfigDir 'opencode.jsonc' }

if (Test-Path -LiteralPath $cfgPath) {
    if ($RestoreConfig -and $latestBackup) {
        $candidate = Join-Path $latestBackup.FullName 'opencode.json'
        if (Test-Path -LiteralPath $candidate) {
            if ($DryRun) { Write-Step "restore opencode.json from backup" }
            else {
                Copy-Item -LiteralPath $cfgPath -Destination "$cfgPath.before-restore" -Force
                Copy-Item -LiteralPath $candidate -Destination $cfgPath -Force
                Write-Ok "opencode.json 已从备份恢复"
            }
        } else {
            Write-Warn2 "备份中没有 opencode.json，改为删除插件条目"
            $RestoreConfig = $false
        }
    }

    if (-not $RestoreConfig) {
        try {
            $text = [System.IO.File]::ReadAllText($cfgPath, $Utf8)
            $cfg = $text | ConvertFrom-Json
            $kept = @()
            $removed = 0
            if ($cfg.PSObject.Properties.Name -contains 'plugins' -and $cfg.plugins) {
                foreach ($p in @($cfg.plugins)) {
                    $pkgName = if ($p -is [string]) { $p } else { $p.package }
                    if ($pkgName -and ($pkgName -like '*unrestricted*')) { $removed++; continue }
                    $kept += $p
                }
            }
            if ($removed -gt 0) {
                if ($kept.Count -eq 0) {
                    $cfg.PSObject.Properties.Remove('plugins')
                } else {
                    $cfg | Add-Member -NotePropertyName plugins -NotePropertyValue $kept -Force
                }
                if ($DryRun) { Write-Step "remove $removed plugin entry" }
                else {
                    Copy-Item -LiteralPath $cfgPath -Destination "$cfgPath.bak-$((Get-Date -Format 'yyyyMMdd-HHmmss'))" -Force
                    [System.IO.File]::WriteAllText($cfgPath, (($cfg | ConvertTo-Json -Depth 100) + "`r`n"), $Utf8)
                    Write-Ok "已移除 $removed 个插件条目"
                }
            } else {
                Write-Ok "没有找到 unrestricted 插件条目"
            }
        } catch {
            Write-Warn2 "opencode.json 无法自动解析（可能是 JSONC），请手动删除 package 含 unrestricted 的条目"
        }
    }
} else {
    Write-Warn2 "未找到 opencode.json"
}

# ── 3. AGENTS.md 块 ─────────────────────────────────────────────────────────
Write-Host "[3/4] 清理 AGENTS.md" -ForegroundColor White
$agentsMd = Join-Path $ConfigDir 'AGENTS.md'
if (Test-Path -LiteralPath $agentsMd) {
    $existing = [System.IO.File]::ReadAllText($agentsMd, $Utf8)
    $pattern = '(?s)\s*<!-- BEGIN UNRESTRICTED-LAB -->.*?<!-- END UNRESTRICTED-LAB -->\s*'
    if ([regex]::IsMatch($existing, $pattern)) {
        $updated = ([regex]::Replace($existing, $pattern, "`r`n")).Trim() + "`r`n"
        if ($DryRun) { Write-Step "strip UNRESTRICTED-LAB block" }
        else {
            Copy-Item -LiteralPath $agentsMd -Destination "$agentsMd.bak-$((Get-Date -Format 'yyyyMMdd-HHmmss'))" -Force
            if ([string]::IsNullOrWhiteSpace($updated)) { Remove-Item -LiteralPath $agentsMd -Force }
            else { [System.IO.File]::WriteAllText($agentsMd, $updated, $Utf8) }
            Write-Ok "UNRESTRICTED-LAB 块已移除"
        }
    } else {
        Write-Ok "没有找到标记块"
    }
}

# ── 4. 可选：agents / commands / lab-scope ──────────────────────────────────
Write-Host "[4/4] 可选清理" -ForegroundColor White

if ($RemoveFiles) {
    $targets = @(
        'agents\unrestricted.md',
        'agents\redteam.md',
        'commands\unrestricted.md',
        'commands\external.md',
        'commands\apk.md',
        'commands\bypass.md',
        'commands\exploit.md',
        'commands\scope.md'
    )
    foreach ($rel in $targets) {
        $dest = Join-Path $ConfigDir $rel
        $backup = if ($latestBackup) { Join-Path $latestBackup.FullName $rel } else { $null }
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            if ($DryRun) { Write-Step "restore $rel" }
            else { Copy-Item -LiteralPath $backup -Destination $dest -Force; Write-Step "restored $rel" }
        } else {
            Remove-Safe $dest
        }
    }
} else {
    Write-Ok "保留 agents / commands（使用 -RemoveFiles 清理）"
}

if ($PurgeScope) {
    Remove-Safe (Join-Path $ConfigDir 'lab-scope.json')
} else {
    Write-Ok "保留 lab-scope.json 审计记录（使用 -PurgeScope 删除）"
}

Write-Host ""
Write-Host "卸载完成。重载服务：opencode service restart" -ForegroundColor Magenta
