# Contributing / 贡献指南

## English

### Quick start

```bash
brew install xcodegen
git clone https://github.com/YOUR_USERNAME/codextoken.git
cd codextoken
xcodegen generate
open CodexToken.xcodeproj
```

### Rules

1. **Core vs App** — Business logic → `CodexTokenCore`. UI → `CodexTokenApp`.
2. **Tests** — Core changes need unit tests. Use `InMemoryFileSystem` for file ops.
3. **Localization** — Add strings to **both** `en.lproj` and `zh-Hans.lproj`.
4. **No dependencies** — Don't add third-party packages.
5. **Swift 6** — Strict concurrency, `Sendable` conformance.

### Welcome

Bug fixes · test coverage · docs · localization · performance.

### Needs discussion first

Open an issue before: new network features, storage format changes, new dependencies, major refactors.

---

## 中文

### 快速开始

```bash
brew install xcodegen
git clone https://github.com/YOUR_USERNAME/codextoken.git
cd codextoken
xcodegen generate
open CodexToken.xcodeproj
```

### 规范

1. **Core vs App** — 业务逻辑 → `CodexTokenCore`，UI → `CodexTokenApp`。
2. **测试** — Core 的改动需要单元测试，文件操作用 `InMemoryFileSystem`。
3. **国际化** — `en.lproj` 和 `zh-Hans.lproj` **都要**加字符串。
4. **无依赖** — 不引入第三方包。
5. **Swift 6** — 严格并发，`Sendable` 一致性。

### 欢迎

Bug 修复 · 测试覆盖 · 文档 · 国际化 · 性能优化。

### 需先讨论

新网络功能、存储格式变更、新依赖、重大重构 → 先开 Issue。
