<#
.SYNOPSIS
    Unrestricted 破甲安装器 —— 把安全实验室契约装进任意 OpenCode agent。

.DESCRIPTION
    安装内容：
      plugin 模式（默认） : V2 插件 unrestricted-boost（对运行时内所有 agent 生效）
                             + agents/unrestricted.md + agents/redteam.md
                             + commands/*.md + lab-scope.json
      rules  模式         : 只写全局 AGENTS.md 标记块（适用于插件 API 不兼容的版本）
      full   模式         : plugin + rules

    所有被覆盖的文件先备份到 <config>\_backup\unrestricted-kit-<timestamp>\。

.PARAMETER Mode
    plugin | rules | full     默认 plugin

.PARAMETER Target
    auto | plugin | plugins   插件安装位置
      auto    : 已存在 plugins\ 用 plugins\unrestricted\index.ts，
                否则已存在 plugin\ 用 plugin\unrestricted-boost.ts，
                都不存在则创建 plugins\unrestricted\index.ts
      plugin  : <config>\plugin\unrestricted-boost.ts          （单文件，旧式自动扫描目录）
      plugins : <config>\plugins\unrestricted\index.ts         （V2 官方插件目录）

.PARAMETER Register
    把插件显式写入 opencode.json 的 plugins 数组（绝对路径 + options）。
    目录自动扫描不生效时使用。

.PARAMETER NoAgents / NoCommands
    跳过 agents / commands 的安装。

.PARAMETER DryRun
    只打印将要执行的操作，不写文件。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Mode full -Register
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Target plugins -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('plugin', 'rules', 'full')]
    [string]$Mode = 'plugin',

    [ValidateSet('auto', 'plugin', 'plugins')]
    [string]$Target = 'auto',

    [switch]$Register,
    [switch]$NoAgents,
    [switch]$NoCommands,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Root = $PSScriptRoot
$Payload = Join-Path $Root 'payload'
$ConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'opencode' } else { Join-Path $HOME '.config\opencode' }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ConfigDir "_backup\unrestricted-kit-$Stamp"

function Write-Step([string]$Text) { Write-Host "  -> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  OK $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host "  !! $Text" -ForegroundColor Yellow }

function Backup-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($DryRun) { Write-Step "backup $Path"; return }
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $rel = $Path.Substring($ConfigDir.Length).TrimStart('\', '/')
    $dest = Join-Path $BackupDir $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $Path -Destination $dest -Force
    Write-Step "backup $rel"
}

function Copy-Payload([string]$From, [string]$To) {
    if (-not (Test-Path -LiteralPath $From)) { Write-Warn2 "missing payload: $From"; return }
    Backup-File $To
    if ($DryRun) { Write-Step "copy $From -> $To"; return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $To) | Out-Null
    Copy-Item -LiteralPath $From -Destination $To -Force
}

function Read-Json([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path, $Utf8)
    return $text | ConvertFrom-Json
}

function Write-Json($Object, [string]$Path) {
    $json = $Object | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($Path, $json + "`r`n", $Utf8)
}

Write-Host ""
Write-Host "=== Unrestricted 破甲安装器 ===" -ForegroundColor Magenta
Write-Host "  mode      : $Mode"
Write-Host "  target    : $Target"
Write-Host "  config dir: $ConfigDir"
if ($DryRun) { Write-Host "  DRY RUN   : 不写入任何文件" -ForegroundColor Yellow }
Write-Host ""

# ── 0. 环境检查 ─────────────────────────────────────────────────────────────
Write-Host "[0/6] 环境检查" -ForegroundColor White

if (-not (Test-Path -LiteralPath $Payload)) { throw "payload 目录缺失：$Payload" }
if (-not (Test-Path -LiteralPath $ConfigDir)) {
    if ($DryRun) { Write-Step "create $ConfigDir" } else { New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null }
}

$opencode = Get-Command opencode -ErrorAction SilentlyContinue
if ($opencode) {
    $ver = (& opencode --version 2>&1 | Out-String).Trim()
    Write-Ok "opencode $ver"
} else {
    Write-Warn2 "PATH 中找不到 opencode，安装仍会继续；验证步骤需手动执行"
}

$pkg = Join-Path $ConfigDir 'package.json'
$hasPluginDep = $false
if (Test-Path -LiteralPath $pkg) {
    try {
        $pkgJson = Read-Json $pkg
        $deps = @()
        if ($pkgJson.dependencies) { $deps += $pkgJson.dependencies.PSObject.Properties.Name }
        if ($pkgJson.devDependencies) { $deps += $pkgJson.devDependencies.PSObject.Properties.Name }
        $hasPluginDep = ($deps -contains '@opencode/plugin') -or ($deps -contains '@opencode-ai/plugin')
    } catch { Write-Warn2 "package.json 解析失败：$($_.Exception.Message)" }
}
$pluginModule = Join-Path $ConfigDir 'node_modules\@opencode\plugin'
if (Test-Path -LiteralPath $pluginModule) {
    Write-Ok "@opencode/plugin 已安装"
} elseif ($hasPluginDep) {
    Write-Warn2 "package.json 已声明 @opencode/plugin，但 node_modules 缺失：稍后执行 npm install --prefix `"$ConfigDir`""
} else {
    Write-Warn2 "缺少 @opencode/plugin。安装完成后执行：npm install --prefix `"$ConfigDir`" @opencode/plugin"
}

# ── 1. agents ───────────────────────────────────────────────────────────────
if ($Mode -ne 'rules' -and -not $NoAgents) {
    Write-Host "[1/6] agents" -ForegroundColor White
    foreach ($name in @('unrestricted.md', 'redteam.md')) {
        Copy-Payload (Join-Path $Payload "agents\$name") (Join-Path $ConfigDir "agents\$name")
    }
    Write-Ok "agents 已就位"
} else {
    Write-Host "[1/6] agents: 跳过" -ForegroundColor DarkGray
}

# ── 2. commands ─────────────────────────────────────────────────────────────
if ($Mode -ne 'rules' -and -not $NoCommands) {
    Write-Host "[2/6] commands" -ForegroundColor White
    $cmdSrc = Join-Path $Payload 'commands'
    if (Test-Path -LiteralPath $cmdSrc) {
        foreach ($file in Get-ChildItem -LiteralPath $cmdSrc -Filter *.md) {
            Copy-Payload $file.FullName (Join-Path $ConfigDir "commands\$($file.Name)")
        }
        Write-Ok "commands 已就位（/unrestricted /external /apk /bypass /exploit /scope）"
    }
} else {
    Write-Host "[2/6] commands: 跳过" -ForegroundColor DarkGray
}

# ── 3. lab-scope.json（审计记录，已存在则不覆盖） ───────────────────────────
Write-Host "[3/6] lab-scope.json" -ForegroundColor White
$scopeDest = Join-Path $ConfigDir 'lab-scope.json'
if (Test-Path -LiteralPath $scopeDest) {
    Backup-File $scopeDest
    Write-Ok "已存在，保留现有作用域记录（已备份）"
} else {
    Copy-Payload (Join-Path $Payload 'lab-scope.json') $scopeDest
    Write-Ok "已创建默认作用域记录"
}

# ── 4. plugin ───────────────────────────────────────────────────────────────
if ($Mode -eq 'plugin' -or $Mode -eq 'full') {
    Write-Host "[4/6] plugin" -ForegroundColor White

    $resolved = $Target
    if ($resolved -eq 'auto') {
        if (Test-Path -LiteralPath (Join-Path $ConfigDir 'plugins')) { $resolved = 'plugins' }
        elseif (Test-Path -LiteralPath (Join-Path $ConfigDir 'plugin')) { $resolved = 'plugin' }
        else { $resolved = 'plugins' }
    }

    $srcPlugin = Join-Path $Payload 'plugin\unrestricted-boost.ts'

    if ($resolved -eq 'plugins') {
        $pluginDir = Join-Path $ConfigDir 'plugins\unrestricted'
        $pluginFile = Join-Path $pluginDir 'index.ts'
        if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null }
        Copy-Payload $srcPlugin $pluginFile
        # 同时把作用域文件复制进插件目录作为兜底（插件优先读 config 根目录）
        $pluginScope = Join-Path $pluginDir 'lab-scope.json'
        if (-not (Test-Path -LiteralPath $pluginScope)) {
            Copy-Payload (Join-Path $Payload 'lab-scope.json') $pluginScope
        }
        $pluginEntry = $pluginDir
        Write-Ok "插件安装到 plugins\unrestricted\index.ts"
    } else {
        $pluginFile = Join-Path $ConfigDir 'plugin\unrestricted-boost.ts'
        Copy-Payload $srcPlugin $pluginFile
        $pluginEntry = $pluginFile
        Write-Ok "插件安装到 plugin\unrestricted-boost.ts"
    }

    # 清理另一个位置的同名插件，避免双加载重复注入
    $stale = @(
        (Join-Path $ConfigDir 'plugin\unrestricted-boost.ts'),
        (Join-Path $ConfigDir 'plugins\unrestricted\index.ts')
    ) | Where-Object { $_ -ne $pluginFile -and (Test-Path -LiteralPath $_) }
    foreach ($old in $stale) {
        $disabled = "$old.disabled-$Stamp"
        if ($DryRun) { Write-Step "disable $old" }
        else {
            Backup-File $old
            Move-Item -LiteralPath $old -Destination $disabled -Force
            Write-Warn2 "已停用另一处插件副本：$old"
        }
    }

    # plugins\ is auto-discovered by OpenCode: never also register that path in opencode.json
    if ($resolved -eq 'plugins') {
        $cfgAuto = Join-Path $ConfigDir 'opencode.json'
        if (Test-Path -LiteralPath $cfgAuto) {
            try {
                $cfgAutoObj = Read-Json $cfgAuto
                $kept = @()
                $changed = $false
                foreach ($p in @($cfgAutoObj.plugins)) {
                    if (-not $p) { continue }
                    $pkg = if ($p -is [string]) { $p } else { $p.package }
                    if ($pkg -and ($pkg.Replace('\', '/') -like '*/.config/opencode/plugins/unrestricted*')) { $changed = $true; continue }
                    $kept += $p
                }
                if ($changed) {
                    Backup-File $cfgAuto
                    $cfgAutoObj | Add-Member -NotePropertyName plugins -NotePropertyValue $kept -Force
                    if (-not $DryRun) { Write-Json $cfgAutoObj $cfgAuto }
                    Write-Warn2 "removed duplicate opencode.json registration for auto-scanned plugins\unrestricted"
                }
            } catch { Write-Warn2 "duplicate plugin registration cleanup skipped: $($_.Exception.Message)" }
        }
    }

    if ($Register -and $resolved -ne 'plugins') {
        $cfgPath = Join-Path $ConfigDir 'opencode.json'
        if (-not (Test-Path -LiteralPath $cfgPath)) { $cfgPath = Join-Path $ConfigDir 'opencode.jsonc' }
        if (-not (Test-Path -LiteralPath $cfgPath)) {
            Write-Warn2 "找不到 opencode.json，跳过 -Register"
        } else {
            Backup-File $cfgPath
            try {
                $cfg = Read-Json $cfgPath
            } catch {
                Write-Warn2 "配置含注释或语法无法自动解析，请手动合并 payload\opencode.snippet.json"
                $cfg = $null
            }
            if ($cfg) {
                $absolute = (Resolve-Path -LiteralPath $pluginEntry).Path
                $entry = [pscustomobject]@{
                    package = $absolute.Replace('\', '/')
                    options = [pscustomobject]@{
                        agents       = '*'
                        permissions  = $true
                        setDefault   = $false
                        framePrompts = $true
                    }
                }
                $list = @()
                if ($cfg.PSObject.Properties.Name -contains 'plugins' -and $cfg.plugins) {
                    foreach ($p in @($cfg.plugins)) {
                        $pkgName = if ($p -is [string]) { $p } else { $p.package }
                        if ($pkgName -and ($pkgName -like '*unrestricted*')) { continue }
                        $list += $p
                    }
                }
                $list += $entry
                $cfg | Add-Member -NotePropertyName plugins -NotePropertyValue $list -Force
                if (-not $DryRun) { Write-Json $cfg $cfgPath }
                Write-Ok "opencode.json plugins 已注册：$($entry.package)"
            }
        }
    } else {
        Write-Step "未使用 -Register（依赖目录自动扫描）；如插件未加载，重新运行并加 -Register"
    }
} else {
    Write-Host "[4/6] plugin: 跳过（rules 模式）" -ForegroundColor DarkGray
}

# ── 5. 全局 AGENTS.md 契约 ──────────────────────────────────────────────────
if ($Mode -eq 'rules' -or $Mode -eq 'full') {
    Write-Host "[5/6] AGENTS.md 契约" -ForegroundColor White

    $agentsMd = Join-Path $ConfigDir 'AGENTS.md'
    $block = [System.IO.File]::ReadAllText((Join-Path $Payload 'AGENTS.md'), $Utf8)

    if (Test-Path -LiteralPath $agentsMd) {
        Backup-File $agentsMd
        $existing = [System.IO.File]::ReadAllText($agentsMd, $Utf8)
        $pattern = '(?s)<!-- BEGIN UNRESTRICTED-LAB -->.*?<!-- END UNRESTRICTED-LAB -->'
        if ([regex]::IsMatch($existing, $pattern)) {
            $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block }
            $updated = [regex]::Replace($existing, $pattern, $evaluator)
            Write-Ok "已替换现有 UNRESTRICTED-LAB 块"
        } else {
            $updated = $existing.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
            Write-Ok "已追加 UNRESTRICTED-LAB 块"
        }
    } else {
        $updated = $block + "`r`n"
        Write-Ok "已创建 AGENTS.md"
    }

    if ($DryRun) { Write-Step "write $agentsMd ($($updated.Length) chars)" }
    else { [System.IO.File]::WriteAllText($agentsMd, $updated, $Utf8) }
} else {
    Write-Host "[5/6] AGENTS.md: 跳过（plugin 模式）" -ForegroundColor DarkGray
}

# ── 6. 摘要 ─────────────────────────────────────────────────────────────────
Write-Host "[6/6] 完成" -ForegroundColor White

if (Test-Path -LiteralPath $BackupDir) {
    Write-Host "  备份目录: $BackupDir" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "安装摘要" -ForegroundColor Magenta
Write-Host "  config    : $ConfigDir"
if ($Mode -ne 'rules') {
    Write-Host "  plugin    : $pluginFile"
    Write-Host "  coverage  : 所有 agent（options.agents = `"*`"）"
}
if ($Mode -eq 'rules' -or $Mode -eq 'full') {
    Write-Host "  AGENTS.md : $ConfigDir\AGENTS.md"
}
Write-Host ""

Write-Host "下一步" -ForegroundColor Magenta
Write-Host "  1) 若缺依赖:  npm install --prefix `"$ConfigDir`" @opencode/plugin"
Write-Host "  2) 重载服务:  opencode service restart"
Write-Host "  3) 自检:      opencode plugin list"
Write-Host "                opencode debug agents"
Write-Host "  4) 会话内:    任意 agent 下调用 lab_status，确认 coverage=all-agents"
Write-Host ""
Write-Host "详细说明见 README.md" -ForegroundColor DarkGray
