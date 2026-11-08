---
name: v2rayn-proxy
description: Configure, diagnose and use the local V2RayN proxy for Codex. Use when the user wants Codex (or commands it runs) to go through V2RayN, wants a proxy launcher / auto-start shortcut, changes the proxy port, or when network requests fail with timeouts, connection resets, 403 region errors or "unable to connect" and a proxy may be needed.
metadata:
  short-description: Manage and verify V2RayN proxy for Codex
---

# V2RayN proxy for Codex

This plugin/skill routes OpenAI Codex through the local V2RayN inbound (v2rayN 7.x default:
mixed HTTP+SOCKS port `127.0.0.1:10808`; v2rayN 6.x: SOCKS 10808 / HTTP 10809).

Proxy settings must exist **before** Codex starts (Electron and background runners read them at startup).
This package provides a **launcher** that the user or system starts instead of `ChatGPT.exe`:

1. Finds `v2rayN.exe` and reads `guiConfigs\guiNConfig.json` -> inbound port.
2. Starts v2rayN if the port is not listening; waits up to `waitTimeoutSec`.
3. Probes the port (HTTP CONNECT, then SOCKS5 handshake) to verify protocol.
4. Sets `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`, and syncs `~/.codex/.env`.
5. Launches `ChatGPT.exe` with `--proxy-server=<url>` and `--proxy-bypass-list=<local>;localhost;127.0.0.1;::1`.

All scripts live in `scripts/` next to this skill's root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin>\scripts\<script>.ps1" <args>
```

## Scripts

| Script | Purpose |
| --- | --- |
| `proxy-status.ps1 [-Online] [-Json]` | v2rayN path/running, inbound port, resolved proxy URL, port/protocol check, Codex executable path. `-Online` does a real HTTPS request via the proxy. |
| `proxy-config.ps1 [-Set k=v ...] [-Reset]` | Show/change settings in `%LOCALAPPDATA%\CodexProxy\settings.json`. |
| `Install-Launcher.ps1 [-Startup] [-ReplaceOriginal] [-Uninstall]` | Create the "Codex (Proxy)" Desktop + Start Menu shortcuts; `-Startup` = auto-start at login; `-ReplaceOriginal` rewrites existing Codex shortcuts (with automatic backup). |
| `Start-CodexWithProxy.ps1 [-Restart] [-Quiet] [-Direct] [-DryRun]` | The launcher itself. `-DryRun` prints the command it would run. |

Settings keys: `v2rayNPath`, `codexPath` (0 = dynamic detect), `proxyHost`, `proxyPort` (0 = from v2rayN), `proxyScheme` (auto/http/socks5), `autoStartV2rayN`, `waitTimeoutSec`, `onProxyFailure` (ask/continue/abort), `verifyBeforeLaunch`, `verifyUrl`, `noProxy`, `setElectronFlags`, `syncCodexEnv`.

## Procedures

**Check status / diagnose network failures**
1. Run `proxy-status.ps1` to inspect current endpoints and process statuses.
2. For a real reachability test run `proxy-status.ps1 -Online`.
3. Interpret:
   - v2rayN not found -> set `v2rayNPath`.
   - port not listening -> start v2rayN.
   - online check fails while port is OK -> the V2RayN node/subscription is broken (tell the user to switch node in V2RayN).

**First-time setup**
1. Run `proxy-status.ps1` to confirm detection.
2. Run `Install-Launcher.ps1` (add `-Startup` if user wants auto-start at login, `-ReplaceOriginal` if they want their usual shortcut proxied).
3. Quit Codex and launch from **Codex (Proxy)**.

## Notes
- Do not toggle V2RayN's Windows system proxy; the launcher uses per-process settings.
- Never write V2RayN's own config files; only read `guiNConfig.json`.
- Launcher log: `%LOCALAPPDATA%\CodexProxy\launcher.log`.
