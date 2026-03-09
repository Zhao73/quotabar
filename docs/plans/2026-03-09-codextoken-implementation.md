# CodexToken Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a local-first macOS menu bar app that can detect multiple Codex/OpenAI accounts, show stable local account state plus experimental quota state, and switch the active Codex CLI account quickly.

**Architecture:** The app is split into a testable `CodexTokenCore` framework and a SwiftUI `CodexToken` menu bar app. Core handles account discovery, metadata, quota providers, and CLI switching; the app target owns menu bar presentation, settings, localization, and experimental Codex App actions.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XcodeGen, XCTest

---

### Task 1: Scaffold Project

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `Sources/CodexTokenCore/`
- Create: `Sources/CodexTokenApp/`
- Create: `Tests/CodexTokenCoreTests/`

**Steps:**
1. Define the XcodeGen project with a core framework, app target, and unit tests.
2. Generate the Xcode project.
3. Verify the test scheme can run independently from the app target.

### Task 2: Account Discovery and Metadata

**Files:**
- Create: `Sources/CodexTokenCore/Models/*`
- Create: `Sources/CodexTokenCore/Services/AccountDiscoveryService.swift`
- Create: `Sources/CodexTokenCore/Services/AccountMetadataStore.swift`
- Test: `Tests/CodexTokenCoreTests/AccountDiscoveryServiceTests.swift`

**Steps:**
1. Write failing tests for multi-account discovery, active account detection, and metadata merge.
2. Implement the minimum account parsing and metadata persistence.
3. Run tests and refactor names only after green.

### Task 3: Quota Providers and CLI Switching

**Files:**
- Create: `Sources/CodexTokenCore/Models/QuotaSnapshot.swift`
- Create: `Sources/CodexTokenCore/Services/Quota/*`
- Create: `Sources/CodexTokenCore/Services/CLISwitchService.swift`
- Test: `Tests/CodexTokenCoreTests/LocalStateQuotaProviderTests.swift`
- Test: `Tests/CodexTokenCoreTests/CLISwitchServiceTests.swift`

**Steps:**
1. Write failing tests for local quota state mapping and CLI auth switching.
2. Implement the stable quota provider and experimental provider fallback.
3. Add rollback behavior and shell-status validation hooks for CLI switching.

### Task 4: Menu Bar UI and Localization

**Files:**
- Create: `Sources/CodexTokenApp/*`
- Create: `Resources/en.lproj/Localizable.strings`
- Create: `Resources/zh-Hans.lproj/Localizable.strings`

**Steps:**
1. Build a MenuBarExtra-based UI with account list, refresh, settings, and quick actions.
2. Add settings for language, experimental features, and metadata editing.
3. Wire the app to core services and show stable vs experimental states clearly.

### Task 5: Open-Source Docs and Verification

**Files:**
- Create: `README.md`
- Create: `PRIVACY.md`
- Create: `SECURITY.md`

**Steps:**
1. Document local-first behavior, experimental boundaries, and build steps in Chinese and English.
2. Generate the Xcode project and run fresh tests plus a build.
3. Fix any regressions before reporting completion.
