# Privacy / 隐私政策

**Last updated / 更新时间:** 2026-03-09

---

## English

CodexToken is a **local-first** application.

### What we collect

Nothing. CodexToken makes **zero** network requests for its core features. There is no analytics, no telemetry, no crash reporting, no cloud sync.

### Where your data lives

| Data | Location |
|------|----------|
| Auth tokens | `~/.codex/auth.json` (managed by Codex CLI) |
| Account snapshots | `~/.codex/accounts/` |
| Metadata (names, remarks) | `~/.codex/codex-token-metadata.json` |
| App preferences | macOS `UserDefaults` |

Everything stays on your Mac.

### Experimental features (opt-in)

- **Codex App Server quota** — When enabled, sends HTTPS requests to `api.openai.com` using your existing auth token to fetch quota data. No additional data is sent.
- **Custom quota command** — Executes a shell command you define. CodexToken only reads stdout.

Both are **disabled by default**.

### Third-party code

None. Zero external dependencies.

---

## 中文

CodexToken 是一个 **本地优先** 的应用。

### 数据收集

不收集任何数据。核心功能 **零网络请求**。无分析、无遥测、无崩溃上报、无云同步。

### 数据存储位置

| 数据 | 位置 |
|------|------|
| Auth token | `~/.codex/auth.json`（由 Codex CLI 管理） |
| 账号快照 | `~/.codex/accounts/` |
| 元数据（名称、备注） | `~/.codex/codex-token-metadata.json` |
| 应用偏好设置 | macOS `UserDefaults` |

一切都在你的 Mac 本地。

### 实验性功能（需手动开启）

- **Codex App Server 额度** — 开启后，使用你现有的 auth token 向 `api.openai.com` 发送 HTTPS 请求获取额度。不发送额外数据。
- **自定义额度命令** — 执行你定义的 Shell 命令，只读取 stdout。

两者默认 **关闭**。

### 第三方代码

无。零外部依赖。
