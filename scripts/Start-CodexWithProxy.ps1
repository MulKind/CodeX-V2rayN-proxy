<#
.SYNOPSIS
    Launch Codex through the local V2RayN proxy.

.DESCRIPTION
    1. Locates Codex (ChatGPT.exe / Codex.exe in OpenAI.Codex Appx package or runtimes).
    2. Starts V2RayN if its inbound port is not listening and waits for it.
    3. Sets HTTP_PROXY / HTTPS_PROXY / ALL_PROXY / NO_PROXY for the process tree.
    4. Syncs proxy environment into ~/.codex/.env for background workers and sub-tools.
    5. Starts Codex with --proxy-server / --proxy-bypass-list Chromium flags.

.PARAMETER Restart
    If Codex is already running, close it first so the new proxy settings take effect.
.PARAMETER Quiet
    Never show dialogs (used for the login auto-start shortcut).
.PARAMETER Direct
    Launch Codex without any proxy (escape hatch).
.PARAMETER DryRun
    Print what would be done without starting anything.
#>
[CmdletBinding()]
param(
    [switch]$Restart,
    [switch]$Quiet,
    [switch]$Direct,
    [switch]$DryRun,
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\ProxyCommon.ps1')

function Say([string]$msg, [int]$flags = 64) {
    Write-CdxLog $msg
    Write-Host $msg
    if (-not $Quiet -and -not $DryRun -and ($flags -band 16 -or $flags -band 48)) { [void](Show-CdxPopup -Text $msg -Flags $flags) }
}

function Ask([string]$msg, [bool]$quietDefault) {
    Write-CdxLog "ASK: $msg"
    if ($Quiet -or $DryRun) { return $quietDefault }
    return ((Show-CdxPopup -Text $msg -Flags (4 + 32)) -eq 6)
}

try {
    $settings = Get-CdxSettings
    Write-CdxLog "---- launcher start (Restart=$Restart Quiet=$Quiet Direct=$Direct DryRun=$DryRun)"

    # ---- 1. Codex executable
    $exe = Find-CdxAppPath -Settings $settings
    if (-not $exe) {
        Say "找不到 Codex (ChatGPT.exe / Codex.exe)。请运行: proxy-config.ps1 -Set codexPath=<完整路径>" 16
        exit 1
    }
    Write-CdxLog "Codex executable: $exe"

    # ---- 2. Already running?
    $running = @(Get-Process | Where-Object { $_.ProcessName -ieq 'ChatGPT' -or $_.ProcessName -ieq 'Codex' })
    if ($running.Count -gt 0) {
        $doRestart = $Restart
        if (-not $doRestart) {
            $doRestart = Ask ("Codex 已在运行，新的代理设置只有重启后才会生效。`n`n是否关闭当前 Codex 并通过代理重新启动？`n(选择「否」将直接切换到已运行的窗口)") $false
        }
        if ($doRestart) {
            Write-CdxLog "stopping $($running.Count) running Codex process(es)"
            if (-not $DryRun) {
                $running | ForEach-Object { try { [void]$_.CloseMainWindow() } catch { } }
                $deadline = (Get-Date).AddSeconds(8)
                while ((Get-Date) -lt $deadline -and @(Get-Process | Where-Object { $_.ProcessName -ieq 'ChatGPT' -or $_.ProcessName -ieq 'Codex' }).Count -gt 0) {
                    Start-Sleep -Milliseconds 300
                }
                Get-Process | Where-Object { $_.ProcessName -ieq 'ChatGPT' -or $_.ProcessName -ieq 'Codex' } | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 800
            }
        } else {
            if (-not $DryRun) { Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) }
            exit 0
        }
    }

    $launchArgs = @()
    if (-not $Direct) {
        # ---- 3. Resolve proxy, start v2rayN if needed
        $proxy = Resolve-CdxProxy -Settings $settings
        Write-CdxLog ("proxy candidate {0} (source: {1}, listening: {2}, v2rayN: {3})" -f $proxy.Url, $proxy.Source, $proxy.Listening, $proxy.V2rayNPath)

        if (-not $proxy.Listening -and $settings.autoStartV2rayN -and $proxy.V2rayNPath -and -not $proxy.V2rayNRunning) {
            Write-CdxLog "starting v2rayN: $($proxy.V2rayNPath)"
            if (-not $DryRun) {
                Start-Process -FilePath $proxy.V2rayNPath -WorkingDirectory (Split-Path -Parent $proxy.V2rayNPath)
            }
        }

        if (-not $proxy.Listening -and -not $DryRun) {
            $deadline = (Get-Date).AddSeconds([int]$settings.waitTimeoutSec)
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 500
                if (Test-CdxTcpPort -HostName $proxy.Host -Port $proxy.Port -TimeoutMs 300) { break }
            }
            Start-Sleep -Milliseconds 500
            $proxy = Resolve-CdxProxy -Settings $settings
        }

        $useProxy = $true
        $problem = $null
        if (-not $proxy.Listening) {
            $problem = "V2RayN 代理端口 $($proxy.Host):$($proxy.Port) 未监听（来源: $($proxy.Source)）。"
            if (-not $proxy.V2rayNPath) { $problem += "`n未找到 v2rayN.exe，可运行 proxy-config.ps1 -Set v2rayNPath=<路径>。" }
        } elseif ($proxy.ProtocolOk -eq $false) {
            $problem = "端口 $($proxy.Port) 在监听，但不像是 HTTP/SOCKS5 代理。"
        } elseif ($settings.verifyBeforeLaunch) {
            $online = Test-CdxProxyOnline -Proxy $proxy -Url $settings.verifyUrl
            Write-CdxLog "online check: $($online.Ok) $($online.Detail)"
            if ($online.Ok -eq $false) { $problem = "代理已启动，但无法访问 $($settings.verifyUrl)：$($online.Detail)`n请在 V2RayN 中检查节点是否可用。" }
        }

        if ($problem) {
            switch ([string]$settings.onProxyFailure) {
                'abort'    { Say "$problem`n已取消启动 Codex。" 16; exit 2 }
                'continue' { Write-CdxLog "$problem -> launching anyway"; if ($proxy.Listening) { $useProxy = $true } else { $useProxy = $false } }
                default {
                    if ($proxy.Listening) {
                        $ok = Ask "$problem`n`n仍然通过该代理启动 Codex 吗？`n(选择「否」将不使用代理直接启动)" $true
                        $useProxy = $ok
                    } else {
                        $ok = Ask "$problem`n`n是否不使用代理直接启动 Codex？" $true
                        if (-not $ok) { Write-CdxLog 'user cancelled'; exit 2 }
                        $useProxy = $false
                    }
                }
            }
        }

        if ($useProxy) {
            Set-CdxProxyEnvironment -Proxy $proxy -NoProxy ([string]$settings.noProxy)
            if ($settings.syncCodexEnv) {
                Sync-CodexEnvFile -Proxy $proxy -NoProxy ([string]$settings.noProxy)
            }
            if ($settings.setElectronFlags) {
                $launchArgs += "--proxy-server=$($proxy.ElectronUrl)"
                $launchArgs += '--proxy-bypass-list=<local>;localhost;127.0.0.1;::1'
            }
            Write-CdxLog "using proxy $($proxy.Url)"
        } else {
            Write-CdxLog 'launching WITHOUT proxy'
        }
    } else {
        Write-CdxLog 'Direct mode: launching without proxy'
    }

    $launchArgs += $ExtraArgs
    Write-CdxLog ("exec: `"{0}`" {1}" -f $exe, ($launchArgs -join ' '))
    if ($DryRun) {
        Write-Host "[DryRun] HTTP_PROXY=$env:HTTP_PROXY NO_PROXY=$env:NO_PROXY"
        Write-Host ("[DryRun] `"{0}`" {1}" -f $exe, ($launchArgs -join ' '))
        exit 0
    }
    if ($launchArgs.Count -gt 0) {
        Start-Process -FilePath $exe -ArgumentList $launchArgs -WorkingDirectory (Split-Path -Parent $exe)
    } else {
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe)
    }
    exit 0
} catch {
    Say "启动失败：$($_.Exception.Message)`n日志：$script:CdxLogPath" 16
    exit 1
}
