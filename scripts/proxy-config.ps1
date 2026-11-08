<#
.SYNOPSIS
    View or change the codex-v2rayn-proxy settings (%LOCALAPPDATA%\CodexProxy\settings.json).
.EXAMPLE
    .\proxy-config.ps1                                   # show effective settings
    .\proxy-config.ps1 -Set proxyPort=10809 verifyBeforeLaunch=true
    .\proxy-config.ps1 -Set v2rayNPath=D:\v2rayN-windows-64\v2rayN.exe
    .\proxy-config.ps1 -Reset
#>
[CmdletBinding()]
param([string[]]$Set, [switch]$Reset)

. (Join-Path $PSScriptRoot 'lib\ProxyCommon.ps1')

if ($Reset) {
    if (Test-Path -LiteralPath $script:CdxSettingsPath) { Remove-Item -LiteralPath $script:CdxSettingsPath -Force }
    Write-Host 'Settings reset to defaults.'
}

$defaults = Get-CdxDefaultSettings
$settings = Get-CdxSettings

if ($Set) {
    foreach ($pair in $Set) {
        $idx = $pair.IndexOf('=')
        if ($idx -lt 1) { Write-Error "Invalid '$pair' (expected key=value)"; exit 1 }
        $key = $pair.Substring(0, $idx).Trim()
        $val = $pair.Substring($idx + 1).Trim().Trim('"')
        $match = @($defaults.Keys | Where-Object { $_ -ieq $key })
        if ($match.Count -eq 0) { Write-Error "Unknown key '$key'. Valid: $($defaults.Keys -join ', ')"; exit 1 }
        $key = $match[0]
        $def = $defaults[$key]
        if ($def -is [bool])    { $settings[$key] = @('1', 'true', 'yes', 'on') -contains $val.ToLower() }
        elseif ($def -is [int]) { $settings[$key] = [int]$val }
        else                    { $settings[$key] = $val }
    }
    foreach ($k in @('proxyScheme', 'onProxyFailure')) {
        $allowed = @{ proxyScheme = @('auto', 'http', 'socks5'); onProxyFailure = @('ask', 'continue', 'abort') }[$k]
        if ($allowed -notcontains ([string]$settings[$k]).ToLower()) { Write-Error "$k must be one of: $($allowed -join ', ')"; exit 1 }
    }
    Save-CdxSettings -Settings $settings
    Write-Host "Saved to $script:CdxSettingsPath"
}

Write-Host '=== Effective settings ==='
foreach ($k in $settings.Keys) {
    $mark = ''
    if ("$($settings[$k])" -ne "$($defaults[$k])") { $mark = '  (custom)' }
    Write-Host ('{0,-20} {1}{2}' -f $k, $settings[$k], $mark)
}
