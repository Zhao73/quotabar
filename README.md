<p align="center">
  <img src="docs/images/banner.png" width="720" alt="QuotaBar banner" />
</p>

<h1 align="center">QuotaBar</h1>

<p align="center">
  <strong>A local-first macOS menu bar command center for Codex CLI account switching, quota visibility, and isolated sessions.</strong><br>
  The repository slug stays <code>codextoken</code>, while the outward-facing product brand is now <code>QuotaBar</code>.
</p>

<p align="center">
  <a href="#install"><img src="https://img.shields.io/badge/Install-111827?style=for-the-badge&logo=apple&logoColor=white" /></a>
  <a href="#product-tour"><img src="https://img.shields.io/badge/Product_Tour-2563eb?style=for-the-badge&logoColor=white" /></a>
  <a href="#supported-languages"><img src="https://img.shields.io/badge/Languages-7c3aed?style=for-the-badge&logoColor=white" /></a>
  <a href="README_CN.md"><img src="https://img.shields.io/badge/中文文档-f97316?style=for-the-badge&logoColor=white" /></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_14+-111?style=flat-square&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/UI-Menu_Bar_Control_Center-2563eb?style=flat-square" />
  <img src="https://img.shields.io/badge/Local--First-Yes-16a34a?style=flat-square" />
  <img src="https://img.shields.io/github/license/Zhao73/codextoken?style=flat-square&color=2563eb" />
</p>

<p align="center">
  <img src="docs/images/hero-showcase.png" width="100%" alt="QuotaBar product showcase" />
</p>

## Why QuotaBar

Codex CLI becomes awkward the moment you operate across multiple identities.

You end up hand-editing `~/.codex/auth.json`, second-guessing which account is active, losing track of your 5-hour and weekly windows, and opening disposable shells just to keep sessions separated.

QuotaBar turns that into a real product surface:

- switch the active Codex CLI account with validation and rollback
- compare saved accounts by quota window before you launch work
- attach local remarks so every account stays recognizable
- preserve the current session as a reusable snapshot
- launch isolated CLI sessions with per-account `CODEX_HOME`
- keep local provider diagnostics in one place

---

## Product Tour

<p align="center">
  <img src="docs/images/menu-bar-real.png" width="420" alt="QuotaBar real menu bar icon" />
</p>

<p align="center">
  <em>The menu bar entry is always visible now, with a stable <code>QB</code> badge fallback plus SF Symbol support.</em>
</p>

### Localized Interface Previews

<table>
<tr>
<td width="50%">
  <img src="docs/images/screenshot-en.png" alt="QuotaBar English interface preview" />
</td>
<td width="50%">
  <img src="docs/images/screenshot-zh.png" alt="QuotaBar Chinese interface preview" />
</td>
</tr>
<tr>
<td align="center"><strong>English UI</strong></td>
<td align="center"><strong>中文界面</strong></td>
</tr>
</table>

### Feature Display

<p align="center">
  <img src="docs/images/features-grid.png" width="100%" alt="QuotaBar feature highlights" />
</p>

---

## Highlights

- **Validated account switching**: write the target snapshot into the live CLI, verify it with `codex login status`, and roll back on failure.
- **Built for real multi-account use**: saved snapshots, duplicate merging, hidden one-off sessions, remarks, and stable local ordering are built in.
- **Quota-first workflow**: see 5-hour and weekly windows before you burn the wrong account.
- **Isolated CLI launches**: open a dedicated Terminal session for any account with its own `CODEX_HOME` and copied config.
- **Useful settings instead of filler**: language, startup tab, auto refresh, diagnostics, account management, storage shortcuts, and advanced quota controls.
- **Right-click shortcuts**: refresh, settings, re-login, switch account, import current session, and open CLI directly from the menu bar icon.

---

## Supported Languages

QuotaBar now ships with these built-in interface languages:

- English
- 简体中文
- 繁體中文
- 日本語
- 한국어
- Español
- Português (Brasil)

`Follow System` is also supported, so the app automatically matches macOS when a bundled language pack exists.

---

## Install

> Requirements: macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
git clone https://github.com/Zhao73/codextoken.git
cd codextoken
xcodegen generate
open CodexToken.xcodeproj
```

Then press `⌘R`. The app runs as a menu bar utility.

### Run tests

```bash
xcodebuild test \
  -project CodexToken.xcodeproj \
  -scheme CodexTokenCore \
  -destination 'platform=macOS'
```

---

## Workflow

```mermaid
flowchart LR
    A["~/.codex/accounts/*.json"] --> B["Discover + merge saved accounts"]
    C["~/.codex/auth.json"] --> B
    B --> D["QuotaBar menu surface"]
    D --> E["Switch active CLI account"]
    D --> F["Launch isolated CLI session"]
    D --> G["Edit remarks + snapshots"]
    D --> H["Open settings + diagnostics"]
    E --> I["Validate with codex login status"]
    F --> J["Per-account CODEX_HOME"]
```

---

## Project Structure

| Layer | Responsibility |
| :--- | :--- |
| `CodexTokenCore` | Account discovery, metadata persistence, snapshot import/removal, CLI switching, quota providers |
| `CodexTokenApp` | SwiftUI menu bar UI, settings window, local caches, remarks, Terminal launch flows |
| Local files | `auth.json`, `accounts/*.json`, metadata JSON, copied config for isolated sessions |

### Design choices

- **Atomic switching** keeps failed swaps from corrupting the active CLI session.
- **Bundle-based localization** keeps the app lightweight and dependency-free.
- **Provider snapshots with local fallback** keep quota panels usable even when upstream data is partial.
- **Outward-only rebrand** keeps the stable repo slug and target structure while presenting a cleaner product brand.

---

## Privacy

QuotaBar is local-first.

- No telemetry
- No analytics
- No cloud account sync
- No token relay service
- No third-party runtime dependency for core workflow

See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), and [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

---

<p align="center">
  <strong>QuotaBar</strong> by Zhao73<br>
  If it makes your Codex workflow calmer and faster, consider starring the repo.
</p>
