# CodexToken

一个 macOS 菜单栏工具，用于本地管理多个 [Codex CLI](https://github.com/openai/codex) 账号。切换活跃会话、监控额度、打开隔离的 Terminal 环境——无需云端同步。

[English](README.md)

<p>
  <img src="https://img.shields.io/badge/平台-macOS_14+-111?style=flat&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/协议-MIT-blue?style=flat" />
</p>

<!--
<p>
  <img src="docs/screenshots/menu.png" width="380" />
  <img src="docs/screenshots/settings.png" width="380" />
</p>
-->

## 为什么做这个

如果你在用多个 OpenAI / Codex 账号（个人、工作、测试 Key…），你一定体会过那个烦：手动编辑 `~/.codex/auth.json`、搞不清当前激活的是哪个账号、没办法并排比较额度。CodexToken 解决的就是这些问题。

## 功能

| 功能 | 说明 |
|------|------|
| **自动发现** | 扫描 `~/.codex/accounts/*.json` 和当前 `auth.json`；按 `account_id` 合并重复项；从 JWT claims 提取邮箱和登录方式 |
| **一键切换** | 把选中的快照复制到 `auth.json`，通过 `codex login status` 验证，失败时自动回滚 |
| **隔离 Terminal 启动** | 为每个账号打开独立的 Terminal 窗口，拥有自己的 `CODEX_HOME`，可以同时运行多个 Codex 会话 |
| **额度监控** | 组合式 Provider 链：Codex App Server → 实验性 Shell 命令 → 本地状态兜底；显示 5 小时和每周窗口及置信度 |
| **会话快照** | 把当前 `auth.json` 导入为命名快照；删除或隐藏不再需要的账号 |
| **Siri 快捷指令** | 三个 AppIntent：保存会话、打开 `.codex` 文件夹、定位 `auth.json` |
| **账号元数据** | 自定义显示名、备注、排序——存储在独立的本地 JSON 文件中 |
| **双语** | 完整的 English & 简体中文界面，运行时切换语言（无需重启） |
| **零依赖** | 纯 Swift 6 + SwiftUI + AppKit，没有第三方包 |

## 安装

### 从源码构建

```bash
brew install xcodegen          # 只需一次
git clone https://github.com/Zhao73/codextoken.git
cd codextoken
xcodegen generate
open CodexToken.xcodeproj      # ⌘R 编译运行
```

应用出现在菜单栏（无 Dock 图标 — `LSUIElement = YES`）。

### 运行测试

```bash
xcodebuild test \
  -project CodexToken.xcodeproj \
  -scheme CodexTokenCore \
  -destination 'platform=macOS'
```

## 架构

```
Sources/
├── CodexTokenCore/               # Framework — 无 UI 依赖，完全可测试
│   ├── Infrastructure/
│   │   └── FileSystem.swift      # 协议 + InMemoryFileSystem 用于测试
│   ├── Models/
│   │   ├── CodexAccount.swift    # 账号值类型（id、email、authMode…）
│   │   ├── QuotaSnapshot.swift   # 额度状态（窗口 & 置信度）
│   │   ├── CodexPaths.swift      # ~/.codex 路径常量
│   │   └── AccountMetadata.swift # 自定义名、备注、排序、隐藏标记
│   └── Services/
│       ├── AccountDiscoveryService.swift      # 扫描 + 合并 + 排序
│       ├── CLISwitchService.swift             # 原子切换 + 回滚
│       ├── CLIProfilePreparationService.swift # 按账号隔离 CODEX_HOME
│       ├── AccountSnapshotImportService.swift # auth.json → accounts/
│       ├── AccountSnapshotRemovalService.swift# 删除或隐藏
│       ├── AccountMetadataStore.swift         # 读写元数据 JSON
│       └── Quota/
│           ├── QuotaProviding.swift           # 协议 + 组合链
│           ├── CodexAppServerQuotaProvider.swift # HTTPS 请求 openai.com
│           ├── ExperimentalQuotaProvider.swift # 用户自定义 Shell 命令
│           └── LocalStateQuotaProvider.swift   # 离线兜底
└── CodexTokenApp/                # SwiftUI 菜单栏应用
    ├── CodexTokenApp.swift       # @main MenuBarExtra 入口
    ├── CodexTokenMenuView.swift  # 账号卡片网格
    ├── CodexTokenMenuViewModel.swift  # 全部业务逻辑
    ├── CodexTokenSettingsView.swift   # 设置窗口
    ├── CodexTokenAppIntents.swift     # Siri 快捷指令
    ├── AppPreferences.swift           # 语言 + 功能开关
    ├── TerminalCLILaunchService.swift # launch.command 生成
    ├── CLILaunchRecordStore.swift     # 启动次数 & 时间戳
    ├── QuotaSnapshotCacheStore.swift  # 刷新间保留额度缓存
    └── CodexAppServerAccountLoginService.swift # ChatGPT / API Key 登录流程
```

### 设计要点

- **`FileSystem` 协议** — 所有涉及磁盘的 Service 都接受 `FileSystem`。单元测试用 `InMemoryFileSystem`，生产环境用 `LocalFileSystem`。
- **组合式额度 Provider** — `QuotaProviding` 实现的链式组合。第一个返回 `.available` 或 `.experimental` 的 Provider 胜出，否则尝试下一个。
- **`CODEX_HOME` 隔离** — 当你为某个账号"打开 CLI"时，CodexToken 会创建临时目录并设置 `CODEX_HOME`，让启动的 Codex 进程使用隔离的认证文件。
- **原子切换 + 回滚** — `CLISwitchService` 在覆写前备份当前 `auth.json`。如果 `codex login status` 验证失败，自动恢复备份。

## 数据文件

所有数据都在你 Mac 的 `~/.codex/` 下：

| 文件 | 归属 | 内容 |
|------|------|------|
| `auth.json` | Codex CLI | 当前会话 token |
| `accounts/*.json` | CodexToken | 保存的会话快照 |
| `codex-token-metadata.json` | CodexToken | 显示名、备注、排序 |
| `config.toml` | Codex CLI | CLI 配置（复制到隔离环境中） |

CodexToken 不会把数据发送到任何地方。详见 [PRIVACY.md](PRIVACY.md) 和 [SECURITY.md](SECURITY.md)。

## 贡献

请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE) © zhaojiapeng
