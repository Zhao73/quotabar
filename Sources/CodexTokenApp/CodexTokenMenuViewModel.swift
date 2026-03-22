import AppKit
import CodexTokenCore
import Combine
import Foundation

@MainActor
final class CodexTokenMenuViewModel: ObservableObject {
    enum TokenStatus {
        case valid
        case expiringSoon(minutesLeft: Int)
        case expired
    }

    enum AccountMoveDirection {
        case up
        case down
    }

    struct Notice: Equatable {
        enum Tone: Equatable {
            case info
            case success
            case warning
            case error
        }

        enum Action: Equatable {
            case reloginCurrentCLI
            case refreshNow
            case openSettings
        }

        let text: String
        let tone: Tone
        let action: Action?

        init(text: String, tone: Tone, action: Action? = nil) {
            self.text = text
            self.tone = tone
            self.action = action
        }
    }

    enum MenuTab {
        case overview
        case codex
        case claude
        case antigravity
    }

    struct AccountRow: Identifiable {
        let account: CodexAccount
        let quota: QuotaSnapshot

        var id: String { account.id }
    }

    struct ProviderDiagnostic: Identifiable {
        enum State {
            case connected
            case degraded
            case unavailable
        }

        let provider: ProviderKind
        let title: String
        let statusText: String
        let detailText: String
        let state: State

        var id: String { provider.rawValue }
    }

    enum AccountSwitchExecutionResult: Sendable {
        case success(CLISwitchResult)
        case failure(String)
    }

    @Published private(set) var accounts: [CodexAccount] = []
    @Published private(set) var quotaSnapshots: [String: QuotaSnapshot] = [:]
    @Published private(set) var launchRecords: [String: CLILaunchRecord] = [:]
    @Published private(set) var providerSnapshots: [ProviderKind: QuotaSnapshot] = [:]
    @Published private(set) var antigravityModelsSnapshot: AntigravityModelsSnapshot?
    @Published private(set) var providerDiagnostics: [ProviderKind: ProviderDiagnostic] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var notice: Notice? {
        didSet {
            scheduleNoticeAutoDismissIfNeeded()
        }
    }
    @Published private(set) var lastUpdatedAt: Date?
    @Published var selectedAccountIndex: Int?
    @Published private(set) var switchingAccountStorageKey: String?
    @Published var selectedTab: MenuTab = .codex

    let preferences: AppPreferences
    let paths: CodexPaths
    let metadataURL: URL

    private let fileSystem: any FileSystem
    private let metadataStore: AccountMetadataStore
    private let quotaCacheStore: QuotaSnapshotCacheStore
    private let quotaHistoryStore: QuotaHistoryStore
    private let launchRecordStore: CLILaunchRecordStore
    private let discoveryService: AccountDiscoveryService
    private let profilePreparationService: CLIProfilePreparationService
    private let terminalLaunchService: TerminalCLILaunchService
    private let switchAccountExecutor: @Sendable (CodexAccount) -> AccountSwitchExecutionResult
    private let snapshotImportService: AccountSnapshotImportService
    private let accountRemovalService: AccountSnapshotRemovalService
    private let accountLoader: () throws -> [CodexAccount]
    private let liveQuotaLoader: (@Sendable (CodexAccount) async -> QuotaSnapshot)?
    private let claudeSnapshotLoader: @Sendable () async -> QuotaSnapshot
    private let antigravitySnapshotLoader: @Sendable () async -> QuotaSnapshot
    private let antigravityModelsLoader: @Sendable () async -> AntigravityModelsSnapshot
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private var backgroundRefreshTask: Task<Void, Never>?
    private var accountImportWatchTask: Task<Void, Never>?
    private var noticeDismissTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var selectedAccountStorageKey: String?

    init(
        preferences: AppPreferences,
        fileSystem: any FileSystem = LocalFileSystem(),
        paths: CodexPaths = .live(),
        metadataURL: URL? = nil,
        quotaCacheStore: QuotaSnapshotCacheStore? = nil,
        quotaHistoryStore: QuotaHistoryStore? = nil,
        launchRecordStore: CLILaunchRecordStore? = nil,
        accountLoader: (() throws -> [CodexAccount])? = nil,
        liveQuotaLoader: (@Sendable (CodexAccount) async -> QuotaSnapshot)? = nil,
        claudeSnapshotLoader: (@Sendable () async -> QuotaSnapshot)? = nil,
        antigravitySnapshotLoader: (@Sendable () async -> QuotaSnapshot)? = nil,
        antigravityModelsLoader: (@Sendable () async -> AntigravityModelsSnapshot)? = nil,
        switchAccountExecutor: (@Sendable (CodexAccount) -> AccountSwitchExecutionResult)? = nil
    ) {
        self.preferences = preferences
        self.fileSystem = fileSystem
        self.paths = paths
        self.metadataURL = metadataURL ?? Self.defaultMetadataURL()

        let metadataStore = AccountMetadataStore(fileSystem: fileSystem, metadataURL: self.metadataURL)
        self.metadataStore = metadataStore
        self.quotaCacheStore = quotaCacheStore ?? QuotaSnapshotCacheStore(fileURL: Self.defaultQuotaCacheURL())
        self.quotaHistoryStore = quotaHistoryStore ?? QuotaHistoryStore()
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
        self.switchAccountExecutor = switchAccountExecutor ?? { [paths] account in
            do {
                let result = try CLISwitchService(paths: paths).switchToAccount(account)
                return .success(result)
            } catch let error as CLISwitchError {
                return .failure(error.localizedDescription)
            } catch {
                return .failure(error.localizedDescription)
            }
        }
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
        self.claudeSnapshotLoader = claudeSnapshotLoader ?? Self.defaultClaudeSnapshotLoader
        self.antigravitySnapshotLoader = antigravitySnapshotLoader ?? Self.defaultAntigravitySnapshotLoader
        self.antigravityModelsLoader = antigravityModelsLoader ?? Self.defaultAntigravityModelsLoader
        self.providerDiagnostics = makePlaceholderProviderDiagnostics()
        self.selectedTab = Self.menuTab(for: preferences.startupTab)

        Publishers.CombineLatest(
            preferences.$experimentalQuotaEnabled.removeDuplicates(),
            preferences.$experimentalQuotaCommand.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] _, _ in
            self?.refresh(showSuccessNotice: false)
        }
        .store(in: &cancellables)

        preferences.$autoRefreshEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.startBackgroundRefreshLoop()
                } else {
                    self.backgroundRefreshTask?.cancel()
                    self.backgroundRefreshTask = nil
                    self.autoRefreshTask?.cancel()
                    self.autoRefreshTask = nil
                }
            }
            .store(in: &cancellables)

        startBackgroundRefreshLoop()
    }
    var menuBarTitle: String {
        effectiveCLIAccount?.displayName ?? preferences.string("app.name")
    }

    var menuBarSymbolName: String {
        if isRefreshing || switchingAccountStorageKey != nil {
            return "arrow.trianglehead.clockwise"
        }
        if hasAnyExpiredToken {
            return "exclamationmark.triangle"
        }
        if notice?.tone == .error {
            return "exclamationmark.circle"
        }
        if hasAnyExpiringSoonToken {
            return "clock.badge.exclamationmark"
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

    var selectedAccountRow: AccountRow? {
        if let selectedAccountStorageKey,
           let row = accountRows.first(where: { $0.account.storageKey == selectedAccountStorageKey }) {
            return row
        }

        guard let selectedAccountIndex,
              accountRows.indices.contains(selectedAccountIndex) else {
            if let effectiveCLIStorageKey,
               let row = accountRows.first(where: { $0.account.storageKey == effectiveCLIStorageKey }) {
                return row
            }
            return accountRows.first
        }
        return accountRows[selectedAccountIndex]
    }

    var displayedCodexRow: AccountRow? {
        guard let storageKey = CodexWorkspaceSelection.displayedStorageKey(
            accounts: accounts,
            selectedStorageKey: selectedAccountStorageKey,
            switchingStorageKey: switchingAccountStorageKey
        ) else {
            return nil
        }

        return accountRows.first(where: { $0.account.storageKey == storageKey }) ?? selectedAccountRow
    }

    var displayedCodexStorageKey: String? {
        displayedCodexRow?.account.storageKey
    }

    var overviewSummaries: [ProviderSurfaceSummary] {
        [codexSummary, providerSummary(for: .claude), providerSummary(for: .antigravity)].compactMap { $0 }
    }

    var settingsProviderDiagnostics: [ProviderDiagnostic] {
        [.claude, .antigravity].compactMap { providerDiagnostics[$0] }
    }

    var antigravityModelQuotas: [AntigravityModelsSnapshot.ModelQuota] {
        antigravityModelsSnapshot?.modelQuotas ?? []
    }

    var codexSummary: ProviderSurfaceSummary? {
        guard let row = displayedCodexRow else {
            return nil
        }

        return ProviderSurfaceSummary(
            provider: .codex,
            title: "Codex",
            accountLabel: row.account.email ?? row.account.displayName,
            planLabel: planTypeLabel(for: row.quota),
            snapshot: row.quota,
            primaryTitle: preferences.string("section.session"),
            secondaryTitle: preferences.string("section.weekly"),
            tertiaryTitle: preferences.string("section.credits")
        )
    }

    func providerSummary(for provider: ProviderKind) -> ProviderSurfaceSummary? {
        switch provider {
        case .codex:
            return codexSummary
        case .claude:
            guard let snapshot = providerSnapshots[.claude] else { return nil }
            return ProviderSurfaceSummary(
                provider: .claude,
                title: "Claude",
                accountLabel: accountLabel(for: snapshot),
                planLabel: planTypeLabel(for: snapshot),
                snapshot: snapshot,
                primaryTitle: preferences.string("section.session"),
                secondaryTitle: preferences.string("section.weekly"),
                tertiaryTitle: nil
            )
        case .antigravity:
            guard let snapshot = providerSnapshots[.antigravity] else { return nil }
            return ProviderSurfaceSummary(
                provider: .antigravity,
                title: "Antigravity",
                accountLabel: antigravityModelsSnapshot?.accountEmail ?? antigravityModelsSnapshot?.accountName ?? accountLabel(for: snapshot),
                planLabel: antigravityModelsSnapshot?.planName ?? planTypeLabel(for: snapshot),
                snapshot: snapshot,
                primaryTitle: antigravityModelsSnapshot?.modelQuotas.first?.label ?? warningValue(prefix: "primary label:", in: snapshot) ?? "Claude",
                secondaryTitle: snapshot.secondaryWindow == nil
                    ? nil
                    : (antigravityModelsSnapshot?.modelQuotas.dropFirst().first?.label ?? warningValue(prefix: "secondary label:", in: snapshot) ?? "Gemini Pro"),
                tertiaryTitle: nil
            )
        }
    }

    var selectedChartPoints: [ProviderChartPoint] {
        switch selectedTab {
        case .overview:
            return chartPoints(for: .codex, accountKey: displayedCodexRow?.account.storageKey)
        case .codex:
            return chartPoints(for: .codex, accountKey: displayedCodexRow?.account.storageKey)
        case .claude:
            return chartPoints(for: .claude, accountKey: nil)
        case .antigravity:
            return chartPoints(for: .antigravity, accountKey: nil)
        }
    }

    var liveSessionNeedsImport: Bool {
        accounts.contains(where: \.isImportedFromActiveSession)
    }

    func menuDidAppear() {
        clearRefreshSuccessNoticeIfNeeded()
        refresh(showSuccessNotice: false)
        if preferences.autoRefreshEnabled {
            startAutoRefreshLoop()
        }
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

    func addAccount() {
        let existingStorageKeys = Set(accounts.map(\.storageKey))

        do {
            let postLoginScript = snapshotImportService.makeCurrentSessionImportShellScript()
            try terminalLaunchService.launchLogin(
                codexDirectory: paths.codexDirectory,
                postLoginScript: postLoginScript
            )
            notice = Notice(
                text: preferences.string("message.accountAddStarted"),
                tone: .success
            )
            watchForImportedAccount(existingStorageKeys: existingStorageKeys)
        } catch {
            notice = Notice(
                text: localizedMessage(for: error, fallbackKey: "message.accountAddFailed"),
                tone: .error
            )
        }
    }

    func showAccount(at index: Int) {
        guard accountRows.indices.contains(index) else { return }
        setSelectedAccount(storageKey: accountRows[index].account.storageKey)
        selectedTab = .codex
    }

    func cycleAccount() {
        let rows = accountRows
        guard !rows.isEmpty else { return }
        let current = selectedAccountRow.flatMap { selectedRow in
            rows.firstIndex(where: { $0.account.storageKey == selectedRow.account.storageKey })
        } ?? 0
        activateAccount(at: (current + 1) % rows.count)
    }

    @discardableResult
    func activateAccount(at index: Int) -> Bool {
        guard accountRows.indices.contains(index) else { return false }
        return activateAccount(storageKey: accountRows[index].account.storageKey)
    }

    @discardableResult
    func activateAccount(storageKey: String) -> Bool {
        guard let targetRow = accountRows.first(where: { $0.account.storageKey == storageKey }) else { return false }

        if switchingAccountStorageKey == storageKey {
            return true
        }

        if targetRow.account.isActiveCLI {
            setSelectedAccount(storageKey: storageKey)
            selectedTab = .codex
            return true
        }

        guard switchingAccountStorageKey == nil else {
            notice = Notice(text: preferences.string("message.cliSwitchInProgress"), tone: .info)
            return false
        }

        let targetAccount = targetRow.account
        let previousStorageKey = effectiveCLIStorageKey ?? selectedAccountStorageKey
        let executor = switchAccountExecutor

        setSelectedAccount(storageKey: storageKey)
        selectedTab = .codex
        switchingAccountStorageKey = storageKey
        notice = Notice(text: preferences.string("message.cliSwitching"), tone: .info)

        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                executor(targetAccount)
            }.value

            await self?.finishAccountSwitch(
                outcome,
                targetStorageKey: storageKey,
                previousStorageKey: previousStorageKey
            )
        }

        return true
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

    func openSelectedCLI() {
        guard let row = displayedCodexRow else { return }
        openCLI(for: row.account)
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

    func copyAccountEmail() {
        guard let row = displayedCodexRow else { return }
        let text = row.account.email ?? row.account.accountID ?? row.account.displayName
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = Notice(text: preferences.string("message.emailCopied"), tone: .success)
    }

    func copyQuotaSummary() {
        guard let row = displayedCodexRow else { return }
        var lines: [String] = []
        lines.append("Account: \(row.account.email ?? row.account.displayName)")
        if let primary = row.quota.primaryWindow {
            lines.append("5h: \(max(0, 100 - primary.usedPercent))% remaining")
        }
        if let secondary = row.quota.secondaryWindow {
            lines.append("Weekly: \(max(0, 100 - secondary.usedPercent))% remaining")
        }
        if let refreshed = row.quota.refreshedAt {
            lines.append("Updated: \(formattedTimestamp(refreshed))")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        notice = Notice(text: preferences.string("message.quotaCopied"), tone: .success)
    }

    func refreshAllProviders() {
        refresh(showSuccessNotice: true)
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
        (NSApp.delegate as? CodexTokenAppDelegate)?.showSettingsWindow(nil)
    }

    func reloginCurrentCLI() {
        do {
            let postLoginScript = snapshotImportService.makeCurrentSessionImportShellScript()
            let existingAuthData = fileSystem.fileExists(at: paths.activeAuthFile)
                ? try? fileSystem.read(from: paths.activeAuthFile)
                : nil
            try terminalLaunchService.launchRelogin(
                codexDirectory: paths.codexDirectory,
                postLoginScript: postLoginScript
            )
            notice = Notice(text: preferences.string("message.reloginStarted"), tone: .info)
            watchForAuthMutation(existingAuthData: existingAuthData)
        } catch {
            notice = Notice(
                text: localizedMessage(for: error, fallbackKey: "message.reloginFailed"),
                tone: .error
            )
        }
    }

    func handleNoticeAction(_ action: Notice.Action) {
        switch action {
        case .reloginCurrentCLI:
            reloginCurrentCLI()
        case .refreshNow:
            refresh(showSuccessNotice: false)
        case .openSettings:
            openSettings()
        }
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
        relativeText(for: lastUpdatedAt)
    }

    func relativeText(for date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = preferences.locale
        let relative = formatter.localizedString(for: date, relativeTo: Date())
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

    func resetCountdownText(for window: QuotaWindowSnapshot?) -> String? {
        guard let window else { return nil }
        return resetCountdownText(for: window.resetsAt)
    }

    func resetCountdownText(for resetDate: Date?) -> String? {
        formattedResetCountdown(for: resetDate, unitsStyle: .abbreviated)
    }

    func detailedResetCountdownText(for window: QuotaWindowSnapshot?) -> String? {
        guard let window else { return nil }
        return detailedResetCountdownText(for: window.resetsAt)
    }

    func detailedResetCountdownText(for resetDate: Date?) -> String? {
        formattedResetCountdown(for: resetDate, unitsStyle: .full)
    }

    private func formattedResetCountdown(
        for resetDate: Date?,
        unitsStyle: DateComponentsFormatter.UnitsStyle
    ) -> String? {
        guard let resetsAt = resetDate else { return nil }
        let now = Date()
        guard resetsAt > now else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = unitsStyle
        formatter.zeroFormattingBehavior = .dropAll
        formatter.calendar = Calendar.current
        formatter.includesApproximationPhrase = false
        formatter.includesTimeRemainingPhrase = false
        return formatter.string(from: now, to: resetsAt)
    }

    func formattedCreditBalance(available: Int?, total: Int?) -> String {
        switch (available, total) {
        case let (available?, total?):
            return "\(available.formatted()) / \(total.formatted())"
        case let (available?, nil):
            return available.formatted()
        case let (nil, total?):
            return total.formatted()
        case (nil, nil):
            return preferences.string("quota.value.unknown")
        }
    }

    func planTypeLabel(for snapshot: QuotaSnapshot) -> String? {
        warningValue(prefix: "plan:", in: snapshot)?
            .capitalized
    }

    func creditsBalanceText(for snapshot: QuotaSnapshot) -> String? {
        warningValue(prefix: "credits balance:", in: snapshot)
    }

    func accountLabel(for snapshot: QuotaSnapshot) -> String? {
        warningValue(prefix: "account:", in: snapshot)
    }

    private static func defaultClaudeSnapshotLoader() async -> QuotaSnapshot {
        await ClaudeOAuthQuotaProvider().snapshot(for: providerProbeAccount(id: "claude-oauth", name: "Claude"))
    }

    private static func defaultAntigravitySnapshotLoader() async -> QuotaSnapshot {
        await AntigravityQuotaProvider().snapshot(for: providerProbeAccount(id: "antigravity", name: "Antigravity"))
    }

    private static func defaultAntigravityModelsLoader() async -> AntigravityModelsSnapshot {
        await AntigravityQuotaProvider().modelsSnapshot(for: providerProbeAccount(id: "antigravity", name: "Antigravity"))
    }

    private static func providerProbeAccount(id: String, name: String) -> CodexAccount {
        CodexAccount(
            id: id,
            storageKey: id,
            sourceFile: nil,
            accountID: id,
            displayName: name,
            remark: nil,
            authMode: .chatGPT,
            lastRefreshAt: nil,
            isActiveCLI: false,
            isImportedFromActiveSession: false
        )
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

    private func providerUnavailableSnapshot(
        sourceLabel: String,
        warning: String
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            status: .unavailable,
            refreshedAt: nil,
            sourceLabel: sourceLabel,
            confidence: .medium,
            warnings: [warning]
        )
    }

    func isTokenExpired(for snapshot: QuotaSnapshot) -> Bool {
        snapshot.warnings.contains("token_expired") || snapshot.warnings.contains("needs_relogin")
    }

    func isTokenExpiringSoon(for snapshot: QuotaSnapshot) -> Bool {
        snapshot.warnings.contains("token_expiring_soon")
    }

    func tokenStatus(for snapshot: QuotaSnapshot) -> TokenStatus {
        if isTokenExpired(for: snapshot) {
            return .expired
        }
        if isTokenExpiringSoon(for: snapshot) {
            if let minutesWarning = snapshot.warnings.first(where: { $0.hasPrefix("expires_in_minutes:") }),
               let minutes = Int(minutesWarning.dropFirst("expires_in_minutes:".count)) {
                return .expiringSoon(minutesLeft: minutes)
            }
            return .expiringSoon(minutesLeft: 0)
        }
        return .valid
    }

    var hasAnyExpiredToken: Bool {
        for row in accountRows {
            if isTokenExpired(for: row.quota) { return true }
        }
        if let claudeSnapshot = providerSnapshots[.claude], isTokenExpired(for: claudeSnapshot) {
            return true
        }
        return false
    }

    var hasAnyExpiringSoonToken: Bool {
        if let claudeSnapshot = providerSnapshots[.claude], isTokenExpiringSoon(for: claudeSnapshot) {
            return true
        }
        return false
    }

    private func warningValue(prefix: String, in snapshot: QuotaSnapshot) -> String? {
        for warning in snapshot.warnings {
            if warning.lowercased().hasPrefix(prefix.lowercased()) {
                return warning.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    func chartPoints(for provider: ProviderKind, accountKey: String?) -> [ProviderChartPoint] {
        quotaHistoryStore.loadAll()
            .filter { $0.providerID == provider.rawValue && $0.accountKey == accountKey }
            .suffix(14)
            .map { ProviderChartPoint(timestamp: $0.timestamp, usedPercent: $0.primaryUsedPercent, secondaryUsedPercent: $0.secondaryUsedPercent) }
    }

    private func appendHistoryRecord(
        provider: ProviderKind,
        accountKey: String?,
        snapshot: QuotaSnapshot
    ) {
        guard let primaryWindow = snapshot.primaryWindow else { return }
        quotaHistoryStore.append(
            ProviderQuotaHistoryRecord(
                providerID: provider.rawValue,
                accountKey: accountKey,
                timestamp: snapshot.refreshedAt ?? Date(),
                primaryUsedPercent: primaryWindow.usedPercent,
                secondaryUsedPercent: snapshot.secondaryWindow?.usedPercent
            )
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

    private func scheduleNoticeAutoDismissIfNeeded() {
        noticeDismissTask?.cancel()

        guard let notice,
              let delay = noticeAutoDismissDelay(for: notice) else {
            noticeDismissTask = nil
            return
        }

        let capturedNotice = notice
        let delayNanoseconds = UInt64(delay * 1_000_000_000)

        noticeDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.dismissNoticeIfUnchanged(capturedNotice)
        }
    }

    private func dismissNoticeIfUnchanged(_ expectedNotice: Notice) {
        guard notice == expectedNotice else { return }
        notice = nil
    }

    private func noticeAutoDismissDelay(for notice: Notice) -> TimeInterval? {
        NoticeAutoDismissPolicy.delay(
            for: noticeAutoDismissTone(for: notice.tone),
            hasAction: notice.action != nil
        )
    }

    private func noticeAutoDismissTone(for tone: Notice.Tone) -> NoticeAutoDismissTone {
        switch tone {
        case .info:
            return .info
        case .success:
            return .success
        case .warning:
            return .info
        case .error:
            return .error
        }
    }

    private func watchForImportedAccount(existingStorageKeys: Set<String>) {
        accountImportWatchTask?.cancel()
        accountImportWatchTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }

                do {
                    let loadedAccounts = try self.accountLoader()
                    let loadedStorageKeys = Set(loadedAccounts.map(\.storageKey))
                    guard loadedStorageKeys != existingStorageKeys else { continue }

                    await MainActor.run {
                        let selectedStorageKey = self.selectedAccountRow?.account.storageKey
                        self.accounts = loadedAccounts
                        self.reselectAccountIfPossible(preferredStorageKey: selectedStorageKey)
                        self.refresh(showSuccessNotice: false)
                    }
                    return
                } catch {
                    continue
                }
            }
        }
    }

    private func watchForAuthMutation(existingAuthData: Data?) {
        accountImportWatchTask?.cancel()
        accountImportWatchTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }

                let currentData = self.fileSystem.fileExists(at: self.paths.activeAuthFile)
                    ? try? self.fileSystem.read(from: self.paths.activeAuthFile)
                    : nil
                guard currentData != existingAuthData else { continue }

                await MainActor.run {
                    self.refresh(showSuccessNotice: false)
                }
                return
            }
        }
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

    private func startBackgroundRefreshLoop() {
        backgroundRefreshTask?.cancel()
        guard preferences.autoRefreshEnabled else { return }
        backgroundRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000_000)
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
            let selectedStorageKey = selectedAccountStorageKey ?? selectedAccountRow?.account.storageKey

            guard generation == refreshGeneration else { return }

            accounts = loadedAccounts
            reselectAccountIfPossible(preferredStorageKey: selectedStorageKey)
            quotaSnapshots = initialSnapshots(
                for: loadedAccounts,
                cachedSnapshots: cachedSnapshots
            )

            await refreshSnapshots(
                for: loadedAccounts,
                cachedSnapshots: &cachedSnapshots,
                generation: generation
            )

            await refreshExternalProviders(generation: generation)

            guard generation == refreshGeneration else { return }

            providerDiagnostics = makeProviderDiagnostics()
            quotaCacheStore.save(cachedSnapshots)
            appendVisibleHistory()
            if switchingAccountStorageKey == nil {
                syncActiveAccountSnapshotIfNeeded()
            }
            if let switchingAccountStorageKey,
               accounts.contains(where: { $0.storageKey == switchingAccountStorageKey && $0.isActiveCLI }) {
                self.switchingAccountStorageKey = nil
            }
            lastUpdatedAt = Date()

            checkTokenHealth()

            if showSuccessNotice && preferences.showRefreshSuccessNotices && notice == nil {
                notice = Notice(text: preferences.string("message.refreshComplete"), tone: .success)
            }
        } catch {
            guard generation == refreshGeneration else { return }
            switchingAccountStorageKey = nil
            notice = Notice(text: localizedMessage(for: error, fallbackKey: "message.refreshFailed"), tone: .error)
        }
    }

    private func checkTokenHealth() {
        if hasAnyExpiredToken {
            notice = Notice(
                text: preferences.string("message.tokenExpired"),
                tone: .error,
                action: .reloginCurrentCLI
            )
            return
        }

        if hasAnyExpiringSoonToken {
            notice = Notice(
                text: preferences.string("message.tokenExpiringSoon"),
                tone: .warning,
                action: .reloginCurrentCLI
            )
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

    private func refreshExternalProviders(generation: Int) async {
        let claudeSnapshotLoader = self.claudeSnapshotLoader
        let antigravitySnapshotLoader = self.antigravitySnapshotLoader
        let antigravityModelsLoader = self.antigravityModelsLoader

        enum ExternalProviderRefreshResult {
            case provider(ProviderKind, QuotaSnapshot)
            case antigravityModels(AntigravityModelsSnapshot)
        }

        await withTaskGroup(of: ExternalProviderRefreshResult.self) { group in
            group.addTask { .provider(.claude, await claudeSnapshotLoader()) }
            group.addTask { .provider(.antigravity, await antigravitySnapshotLoader()) }
            group.addTask { .antigravityModels(await antigravityModelsLoader()) }

            for await result in group {
                guard generation == refreshGeneration else { continue }
                switch result {
                case let .provider(provider, snapshot):
                    providerSnapshots[provider] = snapshot
                case let .antigravityModels(snapshot):
                    antigravityModelsSnapshot = snapshot
                }
            }
        }
    }

    private func appendVisibleHistory() {
        for row in accountRows {
            appendHistoryRecord(
                provider: .codex,
                accountKey: row.account.storageKey,
                snapshot: row.quota
            )
        }

        if let claudeSnapshot = providerSnapshots[.claude] {
            appendHistoryRecord(provider: .claude, accountKey: nil, snapshot: claudeSnapshot)
        }

        if let antigravitySnapshot = providerSnapshots[.antigravity] {
            appendHistoryRecord(provider: .antigravity, accountKey: nil, snapshot: antigravitySnapshot)
        }
    }

    private func syncActiveAccountSnapshotIfNeeded() {
        guard let activeAccount = accounts.first(where: \.isActiveCLI),
              activeAccount.accountID != nil,
              fileSystem.fileExists(at: paths.activeAuthFile)
        else {
            return
        }

        let destination = paths.accountsDirectory.appendingPathComponent("\(activeAccount.storageKey).json")
        let activeData = try? fileSystem.read(from: paths.activeAuthFile)
        let snapshotData = fileSystem.fileExists(at: destination)
            ? try? fileSystem.read(from: destination)
            : nil

        guard let activeData, activeData != snapshotData else {
            return
        }

        try? snapshotImportService.importCurrentSessionSnapshot(
            preferredFileName: activeAccount.storageKey
        )
    }

    private func reselectAccountIfPossible(preferredStorageKey: String? = nil) {
        if let selectedStorageKey = preferredStorageKey,
           accountRows.contains(where: { $0.account.storageKey == selectedStorageKey }) {
            setSelectedAccount(storageKey: selectedStorageKey)
            return
        }

        if let selectedAccountStorageKey,
           accountRows.contains(where: { $0.account.storageKey == selectedAccountStorageKey }) {
            setSelectedAccount(storageKey: selectedAccountStorageKey)
            return
        }

        if let activeStorageKey = accounts.first(where: \.isActiveCLI)?.storageKey {
            setSelectedAccount(storageKey: activeStorageKey)
            return
        }

        setSelectedAccount(storageKey: accountRows.first?.account.storageKey)
    }

    func ensureSelectedAccountIfNeeded() {
        if selectedAccountRow == nil {
            reselectAccountIfPossible()
        }
    }

    func isSwitchingAccount(storageKey: String) -> Bool {
        switchingAccountStorageKey == storageKey
    }

    func isEffectivelyActiveCLI(storageKey: String) -> Bool {
        effectiveCLIStorageKey == storageKey
    }

    func isDisplayedCodexAccount(storageKey: String) -> Bool {
        displayedCodexStorageKey == storageKey
    }

    private var effectiveCLIStorageKey: String? {
        switchingAccountStorageKey ?? accounts.first(where: \.isActiveCLI)?.storageKey
    }

    private var effectiveCLIAccount: CodexAccount? {
        guard let effectiveCLIStorageKey else { return nil }
        return accounts.first(where: { $0.storageKey == effectiveCLIStorageKey })
            ?? selectedAccountRow?.account
    }

    private func setSelectedAccount(storageKey: String?) {
        selectedAccountStorageKey = storageKey

        guard let storageKey else {
            selectedAccountIndex = nil
            return
        }

        if let index = accountRows.firstIndex(where: { $0.account.storageKey == storageKey }) {
            selectedAccountIndex = index
            return
        }

        selectedAccountIndex = accountRows.isEmpty ? nil : 0
    }

    private func finishAccountSwitch(
        _ outcome: AccountSwitchExecutionResult,
        targetStorageKey: String,
        previousStorageKey: String?
    ) {
        switch outcome {
        case .success:
            setSelectedAccount(storageKey: targetStorageKey)
            notice = Notice(text: preferences.string("message.cliSwitched"), tone: .success)
            refresh(showSuccessNotice: false)

        case let .failure(message):
            switchingAccountStorageKey = nil

            let lowerMessage = message.lowercased()
            let authKeywords = ["not logged in", "unauthorized", "auth", "login", "token", "expired", "credential"]
            let isAuthRelated = authKeywords.contains(where: { lowerMessage.contains($0) })

            if isAuthRelated {
                setSelectedAccount(storageKey: targetStorageKey)
                notice = Notice(
                    text: preferences.string("message.switchNeedsRelogin"),
                    tone: .error,
                    action: .reloginCurrentCLI
                )
            } else {
                if let previousStorageKey {
                    setSelectedAccount(storageKey: previousStorageKey)
                } else {
                    reselectAccountIfPossible()
                }
                notice = Notice(
                    text: message,
                    tone: .error,
                    action: .reloginCurrentCLI
                )
            }
            refresh(showSuccessNotice: false)
        }
    }

    private func makeProviderDiagnostics() -> [ProviderKind: ProviderDiagnostic] {
        [
            .claude: makeClaudeDiagnostic(),
            .antigravity: makeAntigravityDiagnostic()
        ]
    }

    private func makeClaudeDiagnostic() -> ProviderDiagnostic {
        let snapshot = providerSnapshots[.claude]
        let credentialsExist = FileManager.default.fileExists(atPath: Self.claudeCredentialURL().path)

        if let snapshot, isConnectedProviderSnapshot(snapshot) {
            return ProviderDiagnostic(
                provider: .claude,
                title: "Claude",
                statusText: preferences.string("provider.status.connected"),
                detailText: providerUsageDetail(
                    snapshot: snapshot,
                    primaryLabel: preferences.string("quota.window.5h"),
                    secondaryLabel: preferences.string("quota.window.weekly")
                ),
                state: .connected
            )
        }

        if credentialsExist {
            return ProviderDiagnostic(
                provider: .claude,
                title: "Claude",
                statusText: preferences.string("provider.status.degraded"),
                detailText: snapshot?.errorDescription ?? preferences.string("provider.claude.settingsHint"),
                state: .degraded
            )
        }

        return ProviderDiagnostic(
            provider: .claude,
            title: "Claude",
            statusText: preferences.string("provider.status.credentialsMissing"),
            detailText: preferences.string("provider.claude.settingsHint"),
            state: .unavailable
        )
    }

    private func makeAntigravityDiagnostic() -> ProviderDiagnostic {
        let snapshot = providerSnapshots[.antigravity]
        let detailedSnapshot = antigravityModelsSnapshot
        let languageServerRunning = Self.antigravityLanguageServerRunning()

        if let snapshot, isConnectedProviderSnapshot(snapshot) {
            return ProviderDiagnostic(
                provider: .antigravity,
                title: "Antigravity",
                statusText: preferences.string("provider.status.connected"),
                detailText: providerUsageDetail(
                    snapshot: snapshot,
                    primaryLabel: detailedSnapshot?.modelQuotas.first?.label ?? warningValue(prefix: "primary label:", in: snapshot) ?? "Claude",
                    secondaryLabel: detailedSnapshot?.modelQuotas.dropFirst().first?.label ?? warningValue(prefix: "secondary label:", in: snapshot)
                ),
                state: .connected
            )
        }

        if languageServerRunning {
            return ProviderDiagnostic(
                provider: .antigravity,
                title: "Antigravity",
                statusText: preferences.string("provider.status.localService"),
                detailText: snapshot?.errorDescription ?? preferences.string("provider.antigravity.runningHint"),
                state: .degraded
            )
        }

        return ProviderDiagnostic(
            provider: .antigravity,
            title: "Antigravity",
            statusText: preferences.string("provider.status.notConnected"),
            detailText: preferences.string("provider.antigravity.settingsHint"),
            state: .unavailable
        )
    }

    private func providerUsageDetail(
        snapshot: QuotaSnapshot,
        primaryLabel: String,
        secondaryLabel: String?
    ) -> String {
        var segments: [String] = []

        if let primaryWindow = snapshot.primaryWindow {
            segments.append("\(primaryLabel) \(max(0, 100 - primaryWindow.usedPercent))%")
        }

        if let secondaryLabel, let secondaryWindow = snapshot.secondaryWindow {
            segments.append("\(secondaryLabel) \(max(0, 100 - secondaryWindow.usedPercent))%")
        }

        if let planLabel = planTypeLabel(for: snapshot) {
            segments.append(planLabel)
        }

        if let updated = relativeText(for: snapshot.refreshedAt) {
            segments.append(updated)
        }

        return segments.isEmpty ? localizedQuotaStatus(snapshot.status) : segments.joined(separator: " · ")
    }

    private func isConnectedProviderSnapshot(_ snapshot: QuotaSnapshot) -> Bool {
        (snapshot.status == .experimental || snapshot.status == .available) && snapshot.primaryWindow != nil
    }

    private static func claudeCredentialURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json")
    }

    private static func antigravityLanguageServerRunning() -> Bool {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax", "-o", "command="]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return false
            }
            let mergedOutput = [
                String(decoding: outputData, as: UTF8.self),
                String(decoding: errorData, as: UTF8.self)
            ].joined(separator: "\n")
            return mergedOutput
                .split(whereSeparator: \.isNewline)
                .contains { line in
                    let command = line.lowercased()
                    return command.contains("language_server_macos")
                        && command.contains("app_data_dir antigravity")
                }
        } catch {
            return false
        }
    }

    private func makePlaceholderProviderDiagnostics() -> [ProviderKind: ProviderDiagnostic] {
        [
            .claude: ProviderDiagnostic(
                provider: .claude,
                title: "Claude",
                statusText: preferences.string("provider.status.notConnected"),
                detailText: preferences.string("provider.claude.settingsHint"),
                state: .unavailable
            ),
            .antigravity: ProviderDiagnostic(
                provider: .antigravity,
                title: "Antigravity",
                statusText: preferences.string("provider.status.notConnected"),
                detailText: preferences.string("provider.antigravity.settingsHint"),
                state: .unavailable
            )
        ]
    }

    private static func menuTab(for startupTab: StartupMenuTab) -> MenuTab {
        switch startupTab {
        case .overview:
            return .overview
        case .codex:
            return .codex
        case .claude:
            return .claude
        case .antigravity:
            return .antigravity
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
