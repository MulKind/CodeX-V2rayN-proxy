<#
.SYNOPSIS
    Install the v2rayn-proxy plugin/skill into Codex and create the proxy launcher shortcuts.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Startup -ReplaceOriginal
#>
[CmdletBinding()]
param(
    [switch]$Startup,
    [switch]$ReplaceOriginal,
    [switch]$NoShortcuts
)
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'scripts\lib\ProxyCommon.ps1')

$skillSrc  = Join-Path $PSScriptRoot 'skills\v2rayn-proxy'
$codexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' })
$skillDest = Join-Path $codexHome 'skills\v2rayn-proxy'

Write-Host "Installing skill -> $skillDest"
if (Test-Path -LiteralPath $skillDest) { Remove-Item -LiteralPath $skillDest -Recurse -Force }
New-Item -ItemType Directory -Path (Split-Path -Parent $skillDest) -Force | Out-Null
Copy-Item -LiteralPath $skillSrc -Destination $skillDest -Recurse -Force

# Windows PowerShell 5.1 needs a BOM to read non-ASCII text in .ps1 files.
$bom = New-Object System.Text.UTF8Encoding($true)
Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -Filter '*.ps1' | ForEach-Object {
    $text = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($_.FullName, $text, $bom)
}
Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

# Pre-sync ~/.codex/.env
$settings = Get-CdxSettings
$proxy    = Resolve-CdxProxy -Settings $settings
Sync-CodexEnvFile -Proxy $proxy -NoProxy ([string]$settings.noProxy)

if (-not $NoShortcuts) {
    $args2 = @{}
    if ($Startup)         { $args2.Startup = $true }
    if ($ReplaceOriginal) { $args2.ReplaceOriginal = $true }
    & (Join-Path $PSScriptRoot 'scripts\Install-Launcher.ps1') @args2
}

Write-Host ''
& (Join-Path $PSScriptRoot 'scripts\proxy-status.ps1')
Write-Host ''
Write-Host 'Done. Launch Codex from the "Codex (Proxy)" shortcut.'
