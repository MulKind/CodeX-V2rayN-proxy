<#
.SYNOPSIS
    Show V2RayN / proxy status for Codex.
.PARAMETER Online
    Also make a real HTTPS request through the proxy (needs network access).
.PARAMETER Json
    Emit machine-readable JSON.
#>
[CmdletBinding()]
param([switch]$Online, [switch]$Json)

. (Join-Path $PSScriptRoot 'lib\ProxyCommon.ps1')

$settings = Get-CdxSettings
$proxy    = Resolve-CdxProxy -Settings $settings
$cdxExe   = Find-CdxAppPath -Settings $settings
$sys      = Get-CdxSystemProxy
$online   = $null
if ($Online) { $online = Test-CdxProxyOnline -Proxy $proxy -Url $settings.verifyUrl }

$cdxRunning = (@(Get-Process | Where-Object { $_.ProcessName -ieq 'ChatGPT' -or $_.ProcessName -ieq 'Codex' }).Count -gt 0)
$envFile    = Join-Path $script:CodexHome '.env'
$envExists  = Test-Path -LiteralPath $envFile

$result = [ordered]@{
    v2rayNPath          = $proxy.V2rayNPath
    v2rayNRunning       = $proxy.V2rayNRunning
    v2rayNInboundPort   = $(if ($proxy.Inbound) { $proxy.Inbound.LocalPort } else { $null })
    v2rayNAllowLan      = $(if ($proxy.Inbound) { $proxy.Inbound.AllowLANConn } else { $null })
    proxyUrl            = $proxy.Url
    proxySource         = $proxy.Source
    portListening       = $proxy.Listening
    protocolOk          = $proxy.ProtocolOk
    onlineCheck         = $(if ($online) { '{0}: {1}' -f $online.Ok, $online.Detail } else { 'skipped (use -Online)' })
    windowsSystemProxy  = $(if ($sys) { '{0}:{1} (enabled={2})' -f $sys.Host, $sys.Port, $sys.Enabled } else { 'none' })
    codexPath           = $cdxExe
    codexRunning        = $cdxRunning
    codexEnvFile        = $(if ($envExists) { $envFile } else { 'not found' })
    currentProcessProxy = $(if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { '(not set)' })
    launchedViaPlugin   = [bool]$env:CODEX_V2RAYN_PROXY
    settingsFile        = $script:CdxSettingsPath
    logFile             = $script:CdxLogPath
}

if ($Json) { ConvertTo-CdxAsciiJson $result; exit 0 }

Write-Host '=== Codex V2RayN proxy status ==='
foreach ($k in $result.Keys) { Write-Host ('{0,-20} {1}' -f $k, $result[$k]) }
Write-Host ''
if (-not $proxy.V2rayNPath)      { Write-Host '[!] v2rayN.exe not found -> proxy-config.ps1 -Set v2rayNPath=<path>' }
elseif (-not $proxy.Listening)   { Write-Host '[!] Proxy port is not listening -> start v2rayN (the launcher does this automatically).' }
elseif ($proxy.ProtocolOk -eq $false) { Write-Host '[!] Port is open but is not an HTTP/SOCKS5 proxy -> check proxyPort.' }
else                             { Write-Host '[OK] Proxy endpoint looks healthy.' }
if (-not $cdxExe)                { Write-Host '[!] Codex executable not found -> proxy-config.ps1 -Set codexPath=<path>' }
else                             { Write-Host '[OK] Codex executable detected.' }
