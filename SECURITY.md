# Security / 安全政策

## English

### Reporting vulnerabilities

Please **do not** open a public issue. Email security concerns to **zhaojiapeng@example.com** with reproduction steps. You'll receive a response within 48 hours.

### How tokens are handled

- Auth tokens are read from `~/.codex/auth.json` at runtime and **never** logged, cached to disk separately, or transmitted by core features.
- JWT payloads are decoded in-memory to extract `email` and `auth_provider`; no claims are persisted.
- API keys are stored only inside local snapshot files under `~/.codex/accounts/`.

### Account switching safety

`CLISwitchService` performs an atomic swap:

1. Read and back up the current `auth.json`
2. Write the selected account's token
3. Run `codex login status` to validate
4. If validation fails → restore the backup automatically

### Isolated Terminal profiles

`CLIProfilePreparationService` creates a per-account directory with its own `.codex/auth.json` and sets `CODEX_HOME`. The launched Codex process never touches the global auth file.

---

## 中文

### 漏洞报告

请 **不要** 开公开 Issue。将安全问题发送至 **zhaojiapeng@example.com** 并附上复现步骤，48 小时内会收到回复。

### Token 处理方式

- Auth token 在运行时从 `~/.codex/auth.json` 读取，**从不**记录日志、单独缓存到磁盘或由核心功能传输。
- JWT payload 在内存中解码以提取 `email` 和 `auth_provider`，不持久化任何 claim。
- API Key 仅存储在 `~/.codex/accounts/` 下的本地快照文件中。

### 账号切换安全性

`CLISwitchService` 执行原子交换：

1. 读取并备份当前 `auth.json`
2. 写入选中账号的 token
3. 运行 `codex login status` 验证
4. 验证失败 → 自动恢复备份

### 隔离的 Terminal 环境

`CLIProfilePreparationService` 为每个账号创建独立目录（含 `.codex/auth.json`）并设置 `CODEX_HOME`，启动的 Codex 进程不会触碰全局 auth 文件。
