<#
.SYNOPSIS
    Create (or remove) shortcuts that start Codex through the V2RayN proxy.

.EXAMPLE
    .\Install-Launcher.ps1                    # Desktop + Start Menu shortcuts
    .\Install-Launcher.ps1 -Startup           # also auto-start (v2rayN + Codex) at login
    .\Install-Launcher.ps1 -ReplaceOriginal   # make existing Codex shortcuts use the proxy too
    .\Install-Launcher.ps1 -Uninstall         # remove proxy shortcuts / restore originals
#>
[CmdletBinding()]
param(
    [string]$Name = 'Codex (Proxy)',
    [switch]$NoDesktop,
    [switch]$NoStartMenu,
    [switch]$Startup,
    [switch]$ReplaceOriginal,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\ProxyCommon.ps1')

$launcher   = Join-Path $PSScriptRoot 'Start-CodexWithProxy.ps1'
$psExe      = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$desktop    = [Environment]::GetFolderPath('Desktop')
$startMenu  = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$startupDir = [Environment]::GetFolderPath('Startup')
$backupDir  = Join-Path $script:CdxDataDir 'shortcut-backup'
$shell      = New-Object -ComObject WScript.Shell

$settings   = Get-CdxSettings
$cdxExe     = Find-CdxAppPath -Settings $settings
$iconPath   = Get-CdxIconLocation -CodexExePath $cdxExe

function New-ProxyShortcut([string]$path, [string]$extra, [int]$windowStyle = 7) {
    $lnk = $shell.CreateShortcut($path)
    $lnk.TargetPath = $psExe
    $lnk.Arguments  = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" {1}' -f $launcher, $extra).Trim()
    $lnk.WorkingDirectory = $PSScriptRoot
    $lnk.WindowStyle = $windowStyle   # 7 = minimized, avoids console window flash
    $lnk.Description = 'Start Codex through the local V2RayN proxy'
    if ($iconPath) {
        $lnk.IconLocation = $iconPath
    } elseif ($cdxExe) {
        $lnk.IconLocation = "$cdxExe,0"
    }
    $lnk.Save()
    Write-Host "  created  $path"
}

$targets = @()
if (-not $NoDesktop)   { $targets += (Join-Path $desktop   "$Name.lnk") }
if (-not $NoStartMenu) { $targets += (Join-Path $startMenu "$Name.lnk") }
$startupLnk = Join-Path $startupDir "$Name.lnk"

# Previous/original Codex shortcuts
$oldProxyLnk = Join-Path $desktop 'Codex-Proxy.lnk'
$originals = @(
    (Join-Path $desktop 'Codex.lnk'),
    (Join-Path $desktop 'ChatGPT.lnk'),
    (Join-Path $startMenu 'Codex.lnk'),
    (Join-Path $startMenu 'ChatGPT.lnk')
)

if ($Uninstall) {
    Write-Host 'Removing Codex proxy shortcuts...'
    foreach ($p in @((Join-Path $desktop "$Name.lnk"), (Join-Path $startMenu "$Name.lnk"), $startupLnk)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Write-Host "  removed  $p" }
    }
    if (Test-Path -LiteralPath $backupDir) {
        foreach ($b in Get-ChildItem -LiteralPath $backupDir -Filter '*.lnk') {
            $map = Join-Path $backupDir ($b.BaseName + '.target.txt')
            if (Test-Path -LiteralPath $map) {
                $dest = (Get-Content -LiteralPath $map -Raw).Trim()
                Copy-Item -LiteralPath $b.FullName -Destination $dest -Force
                Write-Host "  restored $dest"
            }
        }
        Remove-Item -LiteralPath $backupDir -Recurse -Force
    }
    Write-Host 'Done.'
    exit 0
}

if (-not $cdxExe) { Write-Warning 'Codex executable not found yet; shortcuts will work once codexPath is detected or configured.' }

Write-Host 'Creating Codex proxy shortcuts...'
foreach ($t in $targets) { New-ProxyShortcut $t '' }

# Upgrade user's existing Codex-Proxy.lnk if found
if (Test-Path -LiteralPath $oldProxyLnk) {
    Write-Host "  updating existing legacy shortcut: $oldProxyLnk"
    New-ProxyShortcut $oldProxyLnk ''
}

if ($Startup) {
    New-ProxyShortcut $startupLnk '-Quiet'
    Write-Host '  (login auto-start enabled: v2rayN will be started first if needed)'
}

if ($ReplaceOriginal) {
    if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $i = 0
    foreach ($o in $originals) {
        if (-not (Test-Path -LiteralPath $o)) { continue }
        $cur = $shell.CreateShortcut($o)
        if ($cur.TargetPath -ieq $psExe) { Write-Host "  already proxied $o"; continue }
        $i++
        $bk = Join-Path $backupDir ("original$i.lnk")
        Copy-Item -LiteralPath $o -Destination $bk -Force
        Set-Content -LiteralPath (Join-Path $backupDir ("original$i.target.txt")) -Value $o -Encoding UTF8
        New-ProxyShortcut $o ''
        Write-Host "  (backup of original saved to $bk)"
    }
}

Write-Host ''
Write-Host "Launcher : $launcher"
Write-Host "Settings : $script:CdxSettingsPath"
Write-Host "Log      : $script:CdxLogPath"
