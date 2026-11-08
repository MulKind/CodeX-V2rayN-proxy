# ProxyCommon.ps1 - shared helpers for the codex-v2rayn-proxy plugin.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.
# Dot-source this file:  . "$PSScriptRoot\lib\ProxyCommon.ps1"

$script:CdxDataDir      = Join-Path $env:LOCALAPPDATA 'CodexProxy'
$script:CdxSettingsPath = Join-Path $script:CdxDataDir 'settings.json'
$script:CdxLogPath      = Join-Path $script:CdxDataDir 'launcher.log'
$script:CdxTitle        = 'Codex Proxy (V2RayN)'
$script:CodexHome       = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' })

# ---------------------------------------------------------------- settings

function Get-CdxDefaultSettings {
    $s = [ordered]@{}
    $s.v2rayNPath         = ''          # empty = auto detect
    $s.codexPath          = ''          # empty = auto detect (queries OpenAI.Codex Appx / WindowsApps)
    $s.proxyHost          = '127.0.0.1'
    $s.proxyPort          = 0           # 0 = read from v2rayN guiConfigs\guiNConfig.json
    $s.proxyScheme        = 'auto'      # auto | http | socks5
    $s.autoStartV2rayN    = $true       # start v2rayN when the proxy port is not listening
    $s.waitTimeoutSec     = 30          # how long to wait for v2rayN to open its port
    $s.onProxyFailure     = 'ask'       # ask | continue | abort
    $s.verifyBeforeLaunch = $false      # do a real HTTPS request through the proxy before launch
    $s.verifyUrl          = 'https://www.google.com/generate_204'
    $s.noProxy            = 'localhost,127.0.0.1,::1,.local'
    $s.setElectronFlags   = $true       # pass --proxy-server to Codex / ChatGPT.exe
    $s.syncCodexEnv       = $true       # write HTTP_PROXY / HTTPS_PROXY to ~/.codex/.env
    return $s
}

function Get-CdxSettings {
    $s = Get-CdxDefaultSettings
    if (Test-Path -LiteralPath $script:CdxSettingsPath) {
        try {
            $j = Get-Content -LiteralPath $script:CdxSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) {
                if ($s.Contains($p.Name)) { $s[$p.Name] = $p.Value }
            }
        } catch {
            Write-CdxLog "settings.json is invalid, using defaults: $($_.Exception.Message)"
        }
    }
    return $s
}

function Save-CdxSettings {
    param([System.Collections.IDictionary]$Settings)
    if (-not (Test-Path -LiteralPath $script:CdxDataDir)) {
        New-Item -ItemType Directory -Path $script:CdxDataDir -Force | Out-Null
    }
    $json = New-Object PSObject -Property $Settings | Select-Object @($Settings.Keys) | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($script:CdxSettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-CdxLog {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $script:CdxDataDir)) {
            New-Item -ItemType Directory -Path $script:CdxDataDir -Force | Out-Null
        }
        if ((Test-Path -LiteralPath $script:CdxLogPath) -and ((Get-Item -LiteralPath $script:CdxLogPath).Length -gt 512KB)) {
            Move-Item -LiteralPath $script:CdxLogPath -Destination ($script:CdxLogPath + '.old') -Force
        }
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $script:CdxLogPath -Value $line -Encoding UTF8
    } catch { }
}

function Show-CdxPopup {
    # Flags: 16=error 32=question 48=warning 64=info, +4 = Yes/No buttons.
    # Returns 6=Yes 7=No 1=OK -1=timeout.
    param([string]$Text, [int]$Flags = 64, [int]$TimeoutSec = 0)
    try {
        $sh = New-Object -ComObject WScript.Shell
        return $sh.Popup($Text, $TimeoutSec, $script:CdxTitle, $Flags)
    } catch {
        Write-Host $Text
        return -1
    }
}

# ---------------------------------------------------------------- discovery

function Get-CdxShortcutTarget {
    param([string]$NamePattern)
    $dirs = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    )
    $shell = New-Object -ComObject WScript.Shell
    foreach ($d in $dirs) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
        $links = Get-ChildItem -LiteralPath $d -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
                 Where-Object { $_.BaseName -match $NamePattern }
        foreach ($l in $links) {
            $t = $shell.CreateShortcut($l.FullName).TargetPath
            if ($t -and $t.ToLower().EndsWith('.exe') -and (Test-Path -LiteralPath $t)) { return $t }
        }
    }
    return $null
}

function Find-CdxV2rayNPath {
    param([System.Collections.IDictionary]$Settings)
    if ($Settings -and $Settings.v2rayNPath -and (Test-Path -LiteralPath $Settings.v2rayNPath)) {
        return (Resolve-Path -LiteralPath $Settings.v2rayNPath).Path
    }
    $p = Get-Process -Name 'v2rayN' -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
    if ($p) { return $p.Path }

    $t = Get-CdxShortcutTarget -NamePattern '^v2rayN'
    if ($t -and ([System.IO.Path]::GetFileName($t) -ieq 'v2rayN.exe')) { return $t }

    $roots = @()
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -eq 'Fixed' -and $drive.IsReady) { $roots += $drive.RootDirectory.FullName }
    }
    $roots += @($env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs'), $env:USERPROFILE,
                (Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'Downloads'),
                (Join-Path $env:USERPROFILE 'scoop\apps'))
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'v2rayN' }
        foreach ($d in $dirs) {
            foreach ($cand in @((Join-Path $d.FullName 'v2rayN.exe'),
                                (Join-Path $d.FullName 'current\v2rayN.exe'),
                                (Join-Path (Join-Path $d.FullName $d.Name) 'v2rayN.exe'))) {
                if (Test-Path -LiteralPath $cand) { return $cand }
            }
        }
    }
    return $null
}

function Get-CdxV2rayNInbound {
    # Reads <v2rayN dir>\guiConfigs\guiNConfig.json and returns the first inbound.
    param([string]$V2rayNPath)
    if (-not $V2rayNPath) { return $null }
    $dir = Split-Path -Parent $V2rayNPath
    foreach ($cfg in @((Join-Path $dir 'guiConfigs\guiNConfig.json'), (Join-Path $dir 'guiNConfig.json'))) {
        if (-not (Test-Path -LiteralPath $cfg)) { continue }
        try {
            $j = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
            $inb = $null
            if ($j.PSObject.Properties['Inbound'])      { $inb = @($j.Inbound)[0] }
            elseif ($j.PSObject.Properties['inbound'])  { $inb = @($j.inbound)[0] }
            if ($inb -and $inb.LocalPort) {
                return [pscustomobject]@{
                    LocalPort    = [int]$inb.LocalPort
                    Protocol     = [string]$inb.Protocol
                    AllowLANConn = [bool]$inb.AllowLANConn
                    User         = [string]$inb.User
                    Pass         = [string]$inb.Pass
                    ConfigPath   = $cfg
                }
            }
        } catch { Write-CdxLog "cannot parse ${cfg}: $($_.Exception.Message)" }
    }
    return $null
}

function Get-CdxSystemProxy {
    try {
        $k = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $server = [string]$k.ProxyServer
        if ($server -match '(?:^|=)(?<h>[\w\.\-]+):(?<p>\d+)') {
            return [pscustomobject]@{ Host = $Matches['h']; Port = [int]$Matches['p']; Enabled = ($k.ProxyEnable -eq 1) }
        }
    } catch { }
    return $null
}

function Find-CdxAppPath {
    param([System.Collections.IDictionary]$Settings)
    if ($Settings -and $Settings.codexPath -and (Test-Path -LiteralPath $Settings.codexPath)) {
        return (Resolve-Path -LiteralPath $Settings.codexPath).Path
    }

    # 1. Query Appx Package for OpenAI.Codex
    try {
        $pkg = Get-AppxPackage -Name "OpenAI.Codex" -ErrorAction SilentlyContinue | Where-Object { $_.InstallLocation } | Select-Object -First 1
        if ($pkg -and $pkg.InstallLocation) {
            foreach ($sub in @('app\ChatGPT.exe', 'app\Codex.exe')) {
                $cand = Join-Path $pkg.InstallLocation $sub
                if (Test-Path -LiteralPath $cand) { return $cand }
            }
        }
    } catch { }

    # 2. Search WindowsApps for OpenAI.Codex folders (sorted by latest version)
    $winApps = Join-Path $env:ProgramFiles 'WindowsApps'
    if (Test-Path -LiteralPath $winApps) {
        $dirs = Get-ChildItem -LiteralPath $winApps -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'OpenAI.Codex_*' -and $_.Name -notlike '*PrimaryRuntime*' } |
                Sort-Object -Property CreationTime -Descending
        foreach ($d in $dirs) {
            foreach ($sub in @('app\ChatGPT.exe', 'app\Codex.exe')) {
                $cand = Join-Path $d.FullName $sub
                if (Test-Path -LiteralPath $cand) { return $cand }
            }
        }
    }

    # 3. Check LocalAppData OpenAI Codex CLI / runtimes
    $localCodex = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex'
    if (Test-Path -LiteralPath $localCodex) {
        $clis = Get-ChildItem -LiteralPath $localCodex -Recurse -Filter 'codex.exe' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch 'sandbox' } |
                Sort-Object -Property LastWriteTime -Descending
        if ($clis -and $clis.Count -gt 0) { return $clis[0].FullName }
    }

    # 4. Check running process
    $p = Get-Process | Where-Object { $_.ProcessName -ieq 'ChatGPT' -or $_.ProcessName -ieq 'Codex' } |
         Where-Object { $_.Path } | Select-Object -First 1
    if ($p) { return $p.Path }

    # 5. Check desktop / start menu shortcuts
    $t = Get-CdxShortcutTarget -NamePattern '^(Codex|ChatGPT)'
    if ($t) { return $t }

    return $null
}

function Get-CdxIconLocation {
    param([string]$CodexExePath)
    if ($CodexExePath) {
        $appDir = Split-Path -Parent $CodexExePath
        foreach ($ico in @((Join-Path $appDir 'resources\icon-chatgpt.ico'),
                           (Join-Path $appDir 'resources\chatgpt-app-dark.ico'),
                           (Join-Path (Split-Path -Parent $appDir) 'assets\Square150x150Logo.png'))) {
            if (Test-Path -LiteralPath $ico) { return $ico }
        }
        return "$CodexExePath,0"
    }
    return ''
}

# ---------------------------------------------------------------- probing

function Test-CdxTcpPort {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 500)
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $c.EndConnect($ar)
        return $true
    } catch { return $false } finally { $c.Close() }
}

function Test-CdxHttpProxy {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 2000, [string]$Target = 'www.google.com:443')
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $null }
        $c.EndConnect($ar)
        $c.ReceiveTimeout = $TimeoutMs; $c.SendTimeout = $TimeoutMs
        $s = $c.GetStream()
        $req = [System.Text.Encoding]::ASCII.GetBytes("CONNECT $Target HTTP/1.1`r`nHost: $Target`r`nProxy-Connection: close`r`n`r`n")
        $s.Write($req, 0, $req.Length)
        $buf = New-Object byte[] 512
        $n = $s.Read($buf, 0, $buf.Length)
        if ($n -le 0) { return $null }
        $line = ([System.Text.Encoding]::ASCII.GetString($buf, 0, $n) -split "`r?`n")[0]
        if ($line -match '^HTTP/1\.[01] (\d{3})') { return [int]$Matches[1] }
        return $null
    } catch { return $null } finally { $c.Close() }
}

function Test-CdxSocks5 {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 1500)
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $c.EndConnect($ar)
        $c.ReceiveTimeout = $TimeoutMs; $c.SendTimeout = $TimeoutMs
        $s = $c.GetStream()
        $hello = [byte[]](5, 1, 0)
        $s.Write($hello, 0, 3)
        $buf = New-Object byte[] 2
        $n = $s.Read($buf, 0, 2)
        return ($n -eq 2 -and $buf[0] -eq 5 -and $buf[1] -eq 0)
    } catch { return $false } finally { $c.Close() }
}

function Resolve-CdxProxy {
    param([System.Collections.IDictionary]$Settings, [switch]$Quick)
    if (-not $Settings) { $Settings = Get-CdxSettings }

    $v2Path   = Find-CdxV2rayNPath -Settings $Settings
    $inbound  = Get-CdxV2rayNInbound -V2rayNPath $v2Path
    $v2Proc   = Get-Process -Name 'v2rayN' -ErrorAction SilentlyContinue | Select-Object -First 1
    $hostName = [string]$Settings.proxyHost
    if (-not $hostName) { $hostName = '127.0.0.1' }

    $port = [int]$Settings.proxyPort; $source = 'settings.json'
    if ($port -le 0 -and $inbound) { $port = $inbound.LocalPort; $source = 'v2rayN guiNConfig.json' }
    if ($port -le 0) {
        $sys = Get-CdxSystemProxy
        if ($sys -and ($sys.Host -match '^(127\.|localhost)')) { $port = $sys.Port; $source = 'Windows system proxy' }
    }
    if ($port -le 0) { $port = 10808; $source = 'default (10808)' }

    $scheme = ([string]$Settings.proxyScheme).ToLower()
    $listening = Test-CdxTcpPort -HostName $hostName -Port $port -TimeoutMs 400
    $finalPort = $port
    $protocolOk = $null

    if (-not $Quick -and $listening) {
        if ($scheme -eq 'auto' -or $scheme -eq 'http') {
            $code = Test-CdxHttpProxy -HostName $hostName -Port $port
            if ($code) { $scheme = 'http'; $protocolOk = $true }
            elseif (Test-CdxTcpPort -HostName $hostName -Port ($port + 1) -TimeoutMs 400) {
                $code = Test-CdxHttpProxy -HostName $hostName -Port ($port + 1)
                if ($code) { $scheme = 'http'; $finalPort = $port + 1; $protocolOk = $true }
            }
        }
        if ($protocolOk -ne $true -and ($scheme -eq 'auto' -or $scheme -eq 'socks5')) {
            if (Test-CdxSocks5 -HostName $hostName -Port $port) { $scheme = 'socks5'; $protocolOk = $true }
        }
        if ($protocolOk -ne $true) { $protocolOk = $false }
    }
    if ($scheme -eq 'auto') { $scheme = 'http' }

    $authPart = ''
    if ($inbound -and $inbound.User -and $inbound.Pass -and $source -ne 'settings.json') {
        $authPart = '{0}:{1}@' -f [uri]::EscapeDataString($inbound.User), [uri]::EscapeDataString($inbound.Pass)
    }

    return [pscustomobject]@{
        Host          = $hostName
        Port          = $finalPort
        Scheme        = $scheme
        Url           = '{0}://{1}{2}:{3}' -f $scheme, $authPart, $hostName, $finalPort
        ElectronUrl   = '{0}://{1}:{2}' -f $scheme, $hostName, $finalPort
        Source        = $source
        Listening     = $listening
        ProtocolOk    = $protocolOk
        V2rayNPath    = $v2Path
        V2rayNRunning = [bool]$v2Proc
        Inbound       = $inbound
    }
}

function Test-CdxProxyOnline {
    param([pscustomobject]$Proxy, [string]$Url = 'https://www.google.com/generate_204', [int]$TimeoutSec = 8)
    if ($Proxy.Scheme -ne 'http') {
        return [pscustomobject]@{ Ok = $null; Detail = 'online check only supports http proxies' }
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-WebRequest -Uri $Url -Proxy ('http://{0}:{1}' -f $Proxy.Host, $Proxy.Port) -UseBasicParsing -TimeoutSec $TimeoutSec -Method Get
        $sw.Stop()
        return [pscustomobject]@{ Ok = $true; Detail = ('HTTP {0} in {1} ms' -f [int]$r.StatusCode, $sw.ElapsedMilliseconds) }
    } catch {
        return [pscustomobject]@{ Ok = $false; Detail = $_.Exception.Message }
    }
}

function Set-CdxProxyEnvironment {
    param([pscustomobject]$Proxy, [string]$NoProxy)
    $env:HTTP_PROXY  = $Proxy.Url
    $env:HTTPS_PROXY = $Proxy.Url
    $env:ALL_PROXY   = $Proxy.Url
    $env:http_proxy  = $Proxy.Url
    $env:https_proxy = $Proxy.Url
    $env:all_proxy   = $Proxy.Url
    $env:NO_PROXY    = $NoProxy
    $env:no_proxy    = $NoProxy
    $env:CODEX_V2RAYN_PROXY = $Proxy.Url
}

function Sync-CodexEnvFile {
    param([pscustomobject]$Proxy, [string]$NoProxy)
    try {
        if (-not (Test-Path -LiteralPath $script:CodexHome)) {
            New-Item -ItemType Directory -Path $script:CodexHome -Force | Out-Null
        }
        $envFile = Join-Path $script:CodexHome '.env'
        $lines = @(
            "HTTP_PROXY=$($Proxy.Url)",
            "HTTPS_PROXY=$($Proxy.Url)",
            "ALL_PROXY=$($Proxy.Url)",
            "http_proxy=$($Proxy.Url)",
            "https_proxy=$($Proxy.Url)",
            "all_proxy=$($Proxy.Url)",
            "NO_PROXY=$NoProxy",
            "no_proxy=$NoProxy",
            "CODEX_V2RAYN_PROXY=$($Proxy.Url)"
        )
        [System.IO.File]::WriteAllLines($envFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
        Write-CdxLog "synced proxy settings to $envFile"
    } catch {
        Write-CdxLog "failed to sync ~/.codex/.env: $($_.Exception.Message)"
    }
}

function ConvertTo-CdxAsciiJson {
    param($InputObject)
    $json = $InputObject | ConvertTo-Json -Depth 10 -Compress
    return [regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
}
