# CodexToken

A macOS menu bar utility that manages multiple [Codex CLI](https://github.com/openai/codex) accounts locally. Switch active sessions, monitor quota, open isolated Terminal profiles — all without cloud sync.

[中文说明](README_CN.md)

<p>
  <img src="https://img.shields.io/badge/platform-macOS_14+-111?style=flat&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat" />
</p>

<!--
<p>
  <img src="docs/screenshots/menu.png" width="380" />
  <img src="docs/screenshots/settings.png" width="380" />
</p>
-->

## Why

If you use multiple OpenAI / Codex accounts (personal, work, test keys…), you know the pain: manually editing `~/.codex/auth.json`, losing track of which account is active, no way to compare quotas side by side. CodexToken solves this.

## Features

| Feature | Detail |
|---------|--------|
| **Auto-discovery** | Scans `~/.codex/accounts/*.json` and the active `auth.json`; merges duplicates by `account_id`; extracts email and provider from JWT claims |
| **One-click switching** | Copies the selected snapshot to `auth.json`, validates via `codex login status`, auto-rolls back on failure |
| **Isolated Terminal launch** | Opens a dedicated Terminal window per account with its own `CODEX_HOME`, so you can run multiple Codex sessions simultaneously |
| **Quota monitoring** | Composite provider chain: Codex App Server → Experimental shell command → Local state fallback; shows 5-hour & weekly windows with confidence levels |
| **Session snapshots** | Import the current `auth.json` as a named snapshot; delete or hide accounts you no longer need |
| **Siri Shortcuts** | Three AppIntents: save session, open `.codex` folder, reveal `auth.json` |
| **Account metadata** | Custom display names, remarks, sort order — stored in a separate local JSON file |
| **Bilingual** | Full English & 简体中文 UI with runtime language switching (no restart) |
| **Zero dependencies** | Pure Swift 6 + SwiftUI + AppKit. No third-party packages. |

## Install

### Build from source

```bash
brew install xcodegen          # one-time
git clone https://github.com/Zhao73/codextoken.git
cd codextoken
xcodegen generate
open CodexToken.xcodeproj      # ⌘R to build & run
```

The app appears in the menu bar (no Dock icon — `LSUIElement = YES`).

### Run tests

```bash
xcodebuild test \
  -project CodexToken.xcodeproj \
  -scheme CodexTokenCore \
  -destination 'platform=macOS'
```

## Architecture

```
Sources/
├── CodexTokenCore/               # Framework — no UI, fully testable
│   ├── Infrastructure/
│   │   └── FileSystem.swift      # Protocol + InMemoryFileSystem for tests
│   ├── Models/
│   │   ├── CodexAccount.swift    # Account value type (id, email, authMode…)
│   │   ├── QuotaSnapshot.swift   # Quota state with windows & confidence
│   │   ├── CodexPaths.swift      # ~/.codex path constants
│   │   └── AccountMetadata.swift # Custom name, remark, sort, hidden flag
│   └── Services/
│       ├── AccountDiscoveryService.swift      # Scan + merge + sort
│       ├── CLISwitchService.swift             # Atomic switch + rollback
│       ├── CLIProfilePreparationService.swift # Per-account CODEX_HOME
│       ├── AccountSnapshotImportService.swift # auth.json → accounts/
│       ├── AccountSnapshotRemovalService.swift# Delete or hide
│       ├── AccountMetadataStore.swift         # Read/write metadata JSON
│       └── Quota/
│           ├── QuotaProviding.swift           # Protocol + composite
│           ├── CodexAppServerQuotaProvider.swift # HTTPS to openai.com
│           ├── ExperimentalQuotaProvider.swift # User shell command
│           └── LocalStateQuotaProvider.swift   # Offline fallback
└── CodexTokenApp/                # SwiftUI menu bar application
    ├── CodexTokenApp.swift       # @main MenuBarExtra entry
    ├── CodexTokenMenuView.swift  # Account cards grid
    ├── CodexTokenMenuViewModel.swift  # All business logic wiring
    ├── CodexTokenSettingsView.swift   # Settings window
    ├── CodexTokenAppIntents.swift     # Siri Shortcuts
    ├── AppPreferences.swift           # Language + feature toggles
    ├── TerminalCLILaunchService.swift # launch.command generation
    ├── CLILaunchRecordStore.swift     # Launch count & timestamp
    ├── QuotaSnapshotCacheStore.swift  # Persist quota between refreshes
    └── CodexAppServerAccountLoginService.swift # ChatGPT/API-key login flow
```

### Key design decisions

- **`FileSystem` protocol** — Every service that touches disk accepts a `FileSystem`. Unit tests use `InMemoryFileSystem`; production uses `LocalFileSystem`.
- **Composite quota provider** — A chain of `QuotaProviding` implementations. The first provider that returns `.available` or `.experimental` wins; otherwise the next in chain is tried.
- **`CODEX_HOME` isolation** — When you "Open CLI" for an account, CodexToken creates a temp directory with its own `.codex/auth.json` and sets `CODEX_HOME` so the launched Codex process uses that isolated auth.
- **Atomic switching with rollback** — `CLISwitchService` backs up the current `auth.json` before overwriting. If `codex login status` fails afterward, the backup is restored.

## Data files

All data stays in `~/.codex/` on your Mac:

| File | Owner | Content |
|------|-------|---------|
| `auth.json` | Codex CLI | Active session token |
| `accounts/*.json` | CodexToken | Saved session snapshots |
| `codex-token-metadata.json` | CodexToken | Display names, remarks, sort order |
| `config.toml` | Codex CLI | CLI config (copied into isolated profiles) |

CodexToken never sends data anywhere. See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © zhaojiapeng
