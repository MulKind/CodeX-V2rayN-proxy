# Technical Architecture: OpenAI CodeX V2RayN Proxy Suite

本文档详细说明 `codex-v2rayn-proxy` 针对 Windows MSIX 打包特性、Chromium 网络层、环境变量多级派发以及 CodeX Skill 体系的技术设计细节。

---

## 1. 架构挑战：Windows MSIX 应用与动态生命周期

OpenAI CodeX Windows 客户端并非传统的 Inno Setup / NSIS 静态安装软件，而是采用 **Modern Windows App (MSIX / Appx)** 容器化分发：
- **包标识（Package Identity）**：`OpenAI.Codex_2p2nqsd0c76g0`
- **安装物理根目录**：`C:\Program Files\WindowsApps\OpenAI.Codex_<Version>_x64__2p2nqsd0c76g0\`
- **应用入口**：`app\ChatGPT.exe`

### 1.1 静态路径的脆断问题（The Fragile Path Problem）
Windows 商店及自动更新框架在部署 CodeX 新版本时，会直接生成一个带有全新版本号的目录（例如从 `OpenAI.Codex_26.1029.7803.0_...` 更新为 `OpenAI.Codex_26.1103.4239.0_...`），同时清理旧版本目录。
任何通过静态路径（例如桌面的 `.bat` 批处理或指定硬编码路径的 `.lnk` 快捷方式）都会在静默更新后直接抛出 `Target not found` 或 `系统找不到指定的文件` 异常。

### 1.2 动态解析解决方案 (`Find-CdxAppPath`)
本工具通过多层容错回退机制动态解析当前最新可用的真实执行入口：
1. **Appx PackageManager 优先查询**：
   ```powershell
   Get-AppxPackage -Name "OpenAI.Codex" | Where-Object { $_.InstallLocation }
   ```
   实时向 Windows Appx 注册表查询当前用户激活的物理目录。
2. **WindowsApps 目录时间戳逆序回退**：
   若处于受限沙箱或 Appx API 被禁用环境，直接枚举 `C:\Program Files\WindowsApps\OpenAI.Codex_*`，按 `CreationTime` 降序匹配第一条包含 `app\ChatGPT.exe` 的路径。
3. **Local CLI 回退**：
   备用探测 `%LOCALAPPDATA%\OpenAI\Codex\bin\*\codex.exe`。

---

## 2. 网络代理与全域环境流转

```text
┌─────────────────────────────────────────────────────────────┐
│ 用户点击 "Codex (Proxy)"                                    │
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Start-CodexWithProxy.ps1 (启动引擎)                         │
│  ├─ 动态寻址 OpenAI.Codex 最新 ChatGPT.exe                  │
│  ├─ 嗅探 V2RayN (guiNConfig.json -> 127.0.0.1:10808)        │
│  ├─ 端口离线时自动拉起 v2rayN.exe 并轮询等待就绪             │
│  ├─ 双向 Socket 协议探测 (HTTP CONNECT / SOCKS5)            │
│  ├─ 同步配置写入 ~/.codex/.env:                              │
│  │    HTTP_PROXY=http://127.0.0.1:10808                     │
│  │    HTTPS_PROXY=http://127.0.0.1:10808                    │
│  │    ALL_PROXY=http://127.0.0.1:10808                      │
│  │    NO_PROXY=localhost,127.0.0.1,::1,.local               │
│  └─ 构建 Chromium 运行参数:                                  │
│       --proxy-server=http://127.0.0.1:10808                 │
│       --proxy-bypass-list=<local>;localhost;127.0.0.1;::1   │
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ ChatGPT.exe (CodeX Electron 容器)                           │
│  ├─ 浏览器窗口、UI 通信、模型 SSE 流全面走 proxy-server      │
│  ▼                                                          │
│ Background Workers (node_repl / Python 沙箱 / MCP Tools)    │
│  ├─ 自动加载 ~/.codex/.env 中的环境变量                      │
│  └─ 外网请求、Git 操作、网页抓取自动使用代理                │
└─────────────────────────────────────────────────────────────┘
```

### 2.1 为什么必须同步 `~/.codex/.env`？
CodeX 架构中，UI 界面与后台任务往往运行在独立的 Worker 中（例如通过 `node_repl` 或独立的 Python 沙箱）。虽然启动器注入的环境变量会被部分直接子进程继承，但由 Windows 计划任务、命名管道或独立守护进程唤醒的工作流可能读取不到临时的进程环境。
通过在启动前将最新确定的代理信息同步写入 `~/.codex/.env`，实现了**持久化、确定性的多进程环境对齐**。

---

## 3. CodeX 原生 Skill 体系对齐

本项目不仅包含外部启动器，还完整实现了 CodeX 的 Skill 标准规范：

- **目录结构**：
  ```text
  skills/v2rayn-proxy/
  ├── SKILL.md                 # 遵循 YAML frontmatter 标准
  ├── agents/openai.yaml       # 声明界面元数据与 implicit-invocation 策略
  └── references/              # 按需渐进式公开的补充技术参考
      └── configuration.md
  ```
- **渐进式披露机制（Progressive Disclosure）**：
  - `name` 与 `short-description` 常驻在 Agent 的路由上下文。
  - 只有当用户表达“检查代理”、“配置代理端口”或“网络访问报错”时，CodeX 才会展开读取完整的 `SKILL.md`，最大程度节约 Token 与推理窗口。

---

## 4. 健壮性与安全考量

1. **静默拉起无黑框**：
   快捷方式由 `WScript.Shell` 派生，参数指定 `-WindowStyle Hidden` 并采用 `WindowStyle = 7`（Minimized），消除了普通 `.bat` 脚本启动时的黑框闪烁。
2. **多进程并发保护**：
   若 CodeX 已开启，启动器不会产生冲突的多开进程，而是弹出确认对话框提示用户保存当前对话并平滑重启。
3. **只读保护与本地隔离**：
   不触碰 V2RayN 的核心配置文件，不开启全局 WinINet 系统代理，纯净隔离，即装即用。
