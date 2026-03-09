import AppKit
import CodexTokenCore
import Combine
import Foundation

@MainActor
final class CodexTokenMenuViewModel: ObservableObject {
    enum AccountMoveDirection {
        case up
        case down
    }

    struct Notice: Equatable {
        enum Tone: Equatable {
            case info
            case success
            case error
        }

        let text: String
        let tone: Tone
    }

    struct AccountRow: Identifiable {
        let account: CodexAccount
        let quota: QuotaSnapshot

        var id: String { account.id }
    }

    @Published private(set) var accounts: [CodexAccount] = []
    @Published private(set) var quotaSnapshots: [String: QuotaSnapshot] = [:]
    @Published private(set) var launchRecords: [String: CLILaunchRecord] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var notice: Notice?
    @Published private(set) var lastUpdatedAt: Date?

    let preferences: AppPreferences
    let paths: CodexPaths
    let metadataURL: URL

    private let fileSystem: any FileSystem
    private let metadataStore: AccountMetadataStore
    private let quotaCacheStore: QuotaSnapshotCacheStore
    private let launchRecordStore: CLILaunchRecordStore
    private let discoveryService: AccountDiscoveryService
    private let profilePreparationService: CLIProfilePreparationService
    private let terminalLaunchService: TerminalCLILaunchService
    private let switchService: CLISwitchService
    private let snapshotImportService: AccountSnapshotImportService
    private let accountRemovalService: AccountSnapshotRemovalService
    private let accountLoader: () throws -> [CodexAccount]
    private let liveQuotaLoader: (@Sendable (CodexAccount) async -> QuotaSnapshot)?
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        preferences: AppPreferences,
        fileSystem: any FileSystem = LocalFileSystem(),
        paths: CodexPaths = .live(),
        metadataURL: URL? = nil,
        quotaCacheStore: QuotaSnapshotCacheStore? = nil,
        launchRecordStore: CLILaunchRecordStore? = nil,
        accountLoader: (() throws -> [CodexAccount])? = nil,
        liveQuotaLoader: (@Sendable (CodexAccount) async -> QuotaSnapshot)? = nil
    ) {
        self.preferences = preferences
        self.fileSystem = fileSystem
        self.paths = paths
        self.metadataURL = metadataURL ?? Self.defaultMetadataURL()

        let metadataStore = AccountMetadataStore(fileSystem: fileSystem, metadataURL: self.metadataURL)
        self.metadataStore = metadataStore
        self.quotaCacheStore = quotaCacheStore ?? QuotaSnapshotCacheStore(fileURL: Self.defaultQuotaCacheURL())
        self.launchRecordStore = launchRecordStore ?? CLILaunchRecordStore(fileURL: Self.defaultLaunchRecordURL())
        self.discoveryService = AccountDiscoveryService(
            fileSystem: fileSystem,
            paths: paths,
            metadataStore: metadataStore
        )
        self.profilePreparationService = CLIProfilePreparationService(
            fileSystem: fileSystem,
            globalPaths: paths,
            profileRootDirectory: Self.defaultCLIProfilesRootURL()
        )
        self.terminalLaunchService = TerminalCLILaunchService()
        self.switchService = CLISwitchService(fileSystem: fileSystem, paths: paths)
        self.snapshotImportService = AccountSnapshotImportService(fileSystem: fileSystem, paths: paths)
        self.accountRemovalService = AccountSnapshotRemovalService(
            fileSystem: fileSystem,
            paths: paths,
            metadataStore: metadataStore
        )
        self.launchRecords = self.launchRecordStore.load()
        self.accountLoader = accountLoader ?? { [discoveryService = self.discoveryService] in
            try discoveryService.loadAccounts()
        }
        self.liveQuotaLoader = liveQuotaLoader

        Publishers.CombineLatest(
            preferences.$experimentalQuotaEnabled.removeDuplicates(),
            preferences.$experimentalQuotaCommand.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] _, _ in
            self?.refresh(showSuccessNotice: false)
        }
        .store(in: &cancellables)
    }

    var menuBarTitle: String {
        accounts.first(where: \.isActiveCLI)?.displayName ?? preferences.string("app.name")
    }

    var menuBarSymbolName: String {
        if isRefreshing {
            return "arrow.trianglehead.clockwise"
        }
        if notice?.tone == .error {
            return "exclamationmark.circle"
        }
        return accounts.contains(where: \.isActiveCLI)
            ? "person.crop.circle.badge.checkmark"
            : "person.2.circle"
    }

    var accountRows: [AccountRow] {
        accounts.map { account in
            AccountRow(
                account: account,
                quota: quotaSnapshots[account.storageKey] ?? fallbackQuotaSnapshot(for: account)
            )
        }
    }

    var liveSessionNeedsImport: Bool {
        accounts.contains(where: \.isImportedFromActiveSession)
    }

    func menuDidAppear() {
        clearRefreshSuccessNoticeIfNeeded()
        refresh(showSuccessNotice: false)
        startAutoRefreshLoop()
    }

    func menuDidDisappear() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refresh(showSuccessNotice: Bool = true) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            await self?.performRefresh(generation: generation, showSuccessNotice: showSuccessNotice)
        }
    }

    func saveRemark(_ remark: String, for account: CodexAccount) {
        do {
            var allMetadata = try metadataStore.load()
            var metadata = allMetadata[account.storageKey] ?? AccountMetadata()
            let trimmed = remark.trimmingCharacters(in: .whitespacesAndNewlines)
            metadata.remark = trimmed.isEmpty ? nil : trimmed
            allMetadata[account.storageKey] = metadata
            try metadataStore.save(allMetadata)
            if let index = accounts.firstIndex(where: { $0.storageKey == account.storageKey }) {
                accounts[index] = accountWithUpdatedRemark(accounts[index], remark: metadata.remark)
            }
            notice = Notice(text: preferences.string("message.noteSaved"), tone: .success)
        } catch {
            notice = Notice(text: localizedMessage(for: error, fallbackKey: "message.noteSaveFailed"), tone: .error)
        }
    }

    func deleteAccount(_ account: CodexAccount) {
        do {
            let result = try accountRemovalService.removeAccount(account)
            notice = Notice(
                text: preferences.string(
                    result == .removedSnapshot ? "message.accountDeleted" : "message.accountHidden"
                ),
                tone: .success
            )
            refresh(showSuccessNotice: false)
        } catch {
            notice = Notice(
                text: localizedMessage(for: error, fallbackKey: "message.accountDeleteFailed"),
                tone: .error
            )
        }
    }

    func openCLI(for account: CodexAccount) {
        do {
            let context = try profilePreparationService.prepareProfile(for: account)
            try terminalLaunchService.launch(
                context: context,
                accountLabel: account.email ?? account.displayName
            )
            launchRecords = launchRecordStore.recordLaunch(for: account.storageKey)
            notice = Notice(text: preferences.string("message.cliOpened"), tone: .success)
        } catch {
            notice = Notice(text: localizedMessage(for: error, fallbackKey: "message.cliOpenFailed"), tone: .error)
        }
    }

    func importCurrentSession() {
        do {
            _ = try snapshotImportService.importCurrentSessionSnapshot(preferredFileName: nil)
            notice = Notice(text: preferences.string("message.sessionImported"), tone: .success)
            refresh(showSuccessNotice: false)
        } catch {
            notice = Notice(text: localizedImportError(error), tone: .error)
        }
    }

    func canMoveAccount(storageKey: String, direction: AccountMoveDirection) -> Bool {
        guard let sourceIndex = accountRows.map(\.account.storageKey).firstIndex(of: storageKey) else {
            return false
        }

        switch direction {
        case .up:
            return sourceIndex > 0
        case .down:
            return sourceIndex < accountRows.index(before: accountRows.endIndex)
        }
    }

    func moveAccount(storageKey: String, direction: AccountMoveDirection) {
        guard let orderedAccounts = reorderedAccounts(moving: storageKey, direction: direction) else {
            return
        }

        do {
            try persistAccountOrder(orderedAccounts)
            accounts = orderedAccounts
        } catch {
            notice = Notice(text: localizedMessage(for: error, fallbackKey: "message.sortFailed"), tone: .error)
        }
    }

    func revealCodexDirectory() {
        openDirectory(paths.codexDirectory)
    }

    func revealAccountsDirectory() {
        openDirectory(paths.accountsDirectory)
    }

    func revealAuthFile() {
        revealFile(paths.activeAuthFile)
    }

    func revealConfigFile() {
        revealFile(paths.configFile)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func localizedAuthMode(_ mode: CodexAuthMode) -> String {
        switch mode {
        case .chatGPT:
            return preferences.string("meta.authMode.chatgpt")
        case .apiKey:
            return preferences.string("meta.authMode.api_key")
        case .unknown:
            return preferences.string("meta.authMode.unknown")
        }
    }

    func localizedConfidence(_ confidence: QuotaConfidence) -> String {
        switch confidence {
        case .high:
            return preferences.string("meta.confidence.high")
        case .medium:
            return preferences.string("meta.confidence.medium")
        case .low:
            return preferences.string("meta.confidence.low")
        }
    }

    func localizedQuotaStatus(_ status: QuotaStatus) -> String {
        switch status {
        case .available:
            return preferences.string("quota.status.available")
        case .unavailable:
            return preferences.string("quota.status.unavailable")
        case .experimental:
            return preferences.string("quota.status.experimental")
        case .error:
            return preferences.string("quota.status.error")
        }
    }

    func formattedQuotaValue(_ snapshot: QuotaSnapshot) -> String {
        if let primaryWindow = snapshot.primaryWindow {
            let remaining = max(0, 100 - primaryWindow.usedPercent)
            return "\(remaining)%"
        }
        guard let value = snapshot.value else {
            return preferences.string("quota.value.unknown")
        }
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        guard let unit = snapshot.unit, !unit.isEmpty else {
            return number
        }
        return "\(number) \(unit)"
    }

    func formattedTimestamp(_ date: Date?) -> String {
        guard let date else {
            return "—"
        }

        let formatter = DateFormatter()
        formatter.locale = preferences.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func relativeLastUpdatedText() -> String? {
        guard let lastUpdatedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = preferences.locale
        let relative = formatter.localizedString(for: lastUpdatedAt, relativeTo: Date())
        return String(format: preferences.string("menu.lastUpdated"), relative)
    }

    func quotaWindowLabel(_ window: QuotaWindowSnapshot?) -> String? {
        guard let window else { return nil }
        switch window.windowDurationMinutes {
        case 300:
            return preferences.string("quota.window.5h")
        case 10_080:
            return preferences.string("quota.window.weekly")
        case let minutes?:
            return String(format: preferences.string("quota.window.custom"), minutes)
        case nil:
            return preferences.string("quota.window.unknown")
        }
    }

    func quotaWindowRemainingText(_ window: QuotaWindowSnapshot?) -> String? {
        guard let window else { return nil }
        let remaining = max(0, 100 - window.usedPercent)
        return String(format: preferences.string("quota.window.remaining"), remaining)
    }

    static func defaultMetadataURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("CodexToken", isDirectory: true)
            .appendingPathComponent("account-metadata.json")
    }

    static func defaultQuotaCacheURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("CodexToken", isDirectory: true)
            .appendingPathComponent("quota-cache.json")
    }

    static func defaultLaunchRecordURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("CodexToken", isDirectory: true)
            .appendingPathComponent("cli-launch-records.json")
    }

    static func defaultCLIProfilesRootURL(fileManager: FileManager = .default) -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        return caches
            .appendingPathComponent("CodexToken", isDirectory: true)
            .appendingPathComponent("cli-profiles", isDirectory: true)
    }

    private func openDirectory(_ url: URL) {
        guard fileSystem.fileExists(at: url) else {
            notice = Notice(text: preferences.string("message.openFailed"), tone: .error)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func revealFile(_ url: URL) {
        guard fileSystem.fileExists(at: url) else {
            notice = Notice(text: preferences.string("message.openFailed"), tone: .error)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func fallbackQuotaSnapshot(for account: CodexAccount) -> QuotaSnapshot {
        QuotaSnapshot(
            status: .unavailable,
            refreshedAt: account.lastRefreshAt,
            sourceLabel: preferences.string("quota.status.unavailable"),
            confidence: .high
        )
    }

    private func localizedImportError(_ error: Error) -> String {
        if let importError = error as? AccountSnapshotImportError {
            switch importError {
            case .activeAuthMissing:
                return preferences.string("message.noLiveSession")
            case .unreadableAccountIdentifier:
                return preferences.string("message.importMissingIdentifier")
            }
        }
        return localizedMessage(for: error, fallbackKey: "message.noLiveSession")
    }

    private func localizedMessage(for error: Error, fallbackKey: String) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            return preferences.string(fallbackKey)
        }
        return "\(preferences.string(fallbackKey)) \(description)"
    }

    private func clearRefreshSuccessNoticeIfNeeded() {
        guard notice == Notice(
            text: preferences.string("message.refreshComplete"),
            tone: .success
        ) else {
            return
        }
        notice = nil
    }

    private func startAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                self?.runAutomaticRefresh()
            }
        }
    }

    private func runAutomaticRefresh() {
        clearRefreshSuccessNoticeIfNeeded()
        refresh(showSuccessNotice: false)
    }

    private func performRefresh(generation: Int, showSuccessNotice: Bool) async {
        isRefreshing = true
        defer {
            if generation == refreshGeneration {
                isRefreshing = false
            }
        }

        do {
            let loadedAccounts = try accountLoader()
            var cachedSnapshots = quotaCacheStore.load()

            guard generation == refreshGeneration else { return }

            accounts = loadedAccounts
            quotaSnapshots = initialSnapshots(
                for: loadedAccounts,
                cachedSnapshots: cachedSnapshots
            )

            await refreshSnapshots(
                for: loadedAccounts,
                cachedSnapshots: &cachedSnapshots,
                generation: generation
            )

            guard generation == refreshGeneration else { return }

            quotaCacheStore.save(cachedSnapshots)
            lastUpdatedAt = Date()

            if showSuccessNotice {
                notice = Notice(text: preferences.string("message.refreshComplete"), tone: .success)
            }
        } catch {
            guard generation == refreshGeneration else { return }
            notice = Notice(text: localizedMessage(for: error, fallbackKey: "message.refreshFailed"), tone: .error)
        }
    }

    private func initialSnapshots(
        for accounts: [CodexAccount],
        cachedSnapshots: [String: QuotaSnapshot]
    ) -> [String: QuotaSnapshot] {
        accounts.reduce(into: [String: QuotaSnapshot]()) { partialResult, account in
            partialResult[account.storageKey] = quotaSnapshots[account.storageKey]
                ?? cachedSnapshots[account.storageKey]
                ?? fallbackQuotaSnapshot(for: account)
        }
    }

    private func refreshSnapshots(
        for accounts: [CodexAccount],
        cachedSnapshots: inout [String: QuotaSnapshot],
        generation: Int
    ) async {
        let concurrencyLimit = 3
        var nextIndex = 0
        let requests = accounts.map { account in
            PreparedSnapshotLoad(
                account: account,
                request: makeLiveSnapshotRequest(for: account)
            )
        }

        await withTaskGroup(of: SnapshotRefreshResult.self) { group in
            let initialCount = min(concurrencyLimit, requests.count)
            for _ in 0..<initialCount {
                let item = requests[nextIndex]
                nextIndex += 1
                group.addTask { [liveQuotaLoader] in
                    let snapshot = await Self.loadLiveSnapshot(
                        for: item.account,
                        request: item.request,
                        injectedLoader: liveQuotaLoader
                    )
                    return SnapshotRefreshResult(account: item.account, snapshot: snapshot)
                }
            }

            while let result = await group.next() {
                guard generation == refreshGeneration else {
                    group.cancelAll()
                    continue
                }

                let cached = cachedSnapshots[result.account.storageKey]
                let resolved = resolvedSnapshot(
                    live: result.snapshot,
                    cached: cached,
                    account: result.account
                )
                quotaSnapshots[result.account.storageKey] = resolved
                if isCacheable(result.snapshot) {
                    cachedSnapshots[result.account.storageKey] = result.snapshot
                }

                if nextIndex < requests.count {
                    let item = requests[nextIndex]
                    nextIndex += 1
                    group.addTask { [liveQuotaLoader] in
                        let snapshot = await Self.loadLiveSnapshot(
                            for: item.account,
                            request: item.request,
                            injectedLoader: liveQuotaLoader
                        )
                        return SnapshotRefreshResult(account: item.account, snapshot: snapshot)
                    }
                }
            }
        }
    }

    private func reorderedAccounts(
        moving storageKey: String,
        direction: AccountMoveDirection
    ) -> [CodexAccount]? {
        var orderedAccounts = accountRows.map(\.account)
        guard let sourceIndex = orderedAccounts.firstIndex(where: { $0.storageKey == storageKey }) else {
            return nil
        }

        let destinationIndex: Int
        switch direction {
        case .up:
            guard sourceIndex > 0 else { return nil }
            destinationIndex = sourceIndex - 1
        case .down:
            guard sourceIndex < orderedAccounts.index(before: orderedAccounts.endIndex) else { return nil }
            destinationIndex = sourceIndex + 1
        }

        orderedAccounts.swapAt(sourceIndex, destinationIndex)
        return orderedAccounts
    }

    private func persistAccountOrder(_ orderedAccounts: [CodexAccount]) throws {
        var metadata = try metadataStore.load()
        for (index, account) in orderedAccounts.enumerated() {
            var item = metadata[account.storageKey] ?? AccountMetadata()
            item.sortOrder = index
            metadata[account.storageKey] = item
        }
        try metadataStore.save(metadata)
    }

    private func accountWithUpdatedRemark(_ account: CodexAccount, remark: String?) -> CodexAccount {
        CodexAccount(
            id: account.id,
            storageKey: account.storageKey,
            sourceFile: account.sourceFile,
            accountID: account.accountID,
            email: account.email,
            loginProvider: account.loginProvider,
            sortOrder: account.sortOrder,
            displayName: account.displayName,
            remark: remark,
            authMode: account.authMode,
            lastRefreshAt: account.lastRefreshAt,
            isActiveCLI: account.isActiveCLI,
            isImportedFromActiveSession: account.isImportedFromActiveSession
        )
    }

    private func resolvedSnapshot(
        live: QuotaSnapshot,
        cached: QuotaSnapshot?,
        account: CodexAccount
    ) -> QuotaSnapshot {
        if isCacheable(live) {
            return live
        }
        if let cached {
            return cached
        }
        return live.status == .unavailable ? fallbackQuotaSnapshot(for: account) : live
    }

    private func isCacheable(_ snapshot: QuotaSnapshot) -> Bool {
        snapshot.status == .experimental || snapshot.status == .available
    }

    private func makeLiveSnapshotRequest(for account: CodexAccount) -> LiveSnapshotRequest {
        guard preferences.experimentalQuotaEnabled else {
            return .local
        }

        if preferences.experimentalQuotaCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let context = try profilePreparationService.prepareProfile(for: account)
                return .appServer(context.codexHomeDirectory)
            } catch {
                return .preparationFailure(error.localizedDescription)
            }
        }

        let command = preferences.experimentalQuotaCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let shellCommand: String
        if let context = try? profilePreparationService.prepareProfile(for: account) {
            let path = context.codexHomeDirectory.path.hasSuffix("/") ? context.codexHomeDirectory.path : context.codexHomeDirectory.path + "/"
            shellCommand = "CODEX_HOME='\(Self.escapedForSingleQuotes(path))' \(command)"
        } else {
            shellCommand = command
        }
        return .customCommand(shellCommand)
    }

    private static func loadLiveSnapshot(
        for account: CodexAccount,
        request: LiveSnapshotRequest,
        injectedLoader: (@Sendable (CodexAccount) async -> QuotaSnapshot)?
    ) async -> QuotaSnapshot {
        if let injectedLoader {
            return await injectedLoader(account)
        }

        switch request {
        case .local:
            return await LocalStateQuotaProvider().snapshot(for: account)
        case let .appServer(codexHomeDirectory):
            return await CodexAppServerQuotaProvider(
                codexHomeDirectory: codexHomeDirectory
            ).snapshot(for: account)
        case let .customCommand(shellCommand):
            return await CompositeQuotaProvider(
                primary: ExperimentalQuotaProvider(
                    configuration: ExperimentalQuotaConfiguration(
                        shellCommand: shellCommand
                    )
                ),
                fallback: LocalStateQuotaProvider()
            ).snapshot(for: account)
        case let .preparationFailure(description):
            return QuotaSnapshot(
                status: .error,
                refreshedAt: account.lastRefreshAt,
                sourceLabel: "Codex app-server",
                confidence: .medium,
                warnings: ["Failed to prepare isolated Codex profile for this account."],
                errorDescription: description
            )
        }
    }

    private static func escapedForSingleQuotes(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "'\"'\"'")
    }
}

private struct SnapshotRefreshResult: Sendable {
    let account: CodexAccount
    let snapshot: QuotaSnapshot
}

private struct PreparedSnapshotLoad: Sendable {
    let account: CodexAccount
    let request: LiveSnapshotRequest
}

private enum LiveSnapshotRequest: Sendable {
    case local
    case appServer(URL)
    case customCommand(String)
    case preparationFailure(String)
}
