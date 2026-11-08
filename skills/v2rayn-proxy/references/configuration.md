# Codex Proxy Configuration Details

Settings file: `%LOCALAPPDATA%\CodexProxy\settings.json`

## Configuration Options

- `v2rayNPath`: Path to `v2rayN.exe`. Leave empty to auto-detect from fixed drives and running processes.
- `codexPath`: Path to `ChatGPT.exe` or `Codex.exe`. Leave empty to auto-query the `OpenAI.Codex` Appx package.
- `proxyHost`: Proxy address (default: `127.0.0.1`).
- `proxyPort`: Proxy port. Set to `0` to automatically read from V2RayN's `guiConfigs\guiNConfig.json`.
- `proxyScheme`: `auto`, `http`, or `socks5`.
- `autoStartV2rayN`: `true` to launch V2RayN when the port is not listening.
- `waitTimeoutSec`: Seconds to wait for V2RayN to open its listening port.
- `onProxyFailure`: Action when proxy cannot be reached (`ask`, `continue`, or `abort`).
- `verifyBeforeLaunch`: Whether to perform an HTTPS probe to `verifyUrl` before launching Codex.
- `verifyUrl`: URL to probe when `verifyBeforeLaunch` is true.
- `noProxy`: Hosts excluded from proxying (`localhost,127.0.0.1,::1,.local`).
- `setElectronFlags`: Whether to pass `--proxy-server` and `--proxy-bypass-list` to Codex.
- `syncCodexEnv`: Whether to write proxy environment variables to `~/.codex/.env`.
