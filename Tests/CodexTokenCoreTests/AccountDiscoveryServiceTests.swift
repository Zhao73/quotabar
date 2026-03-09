import XCTest
@testable import CodexTokenCore

final class AccountDiscoveryServiceTests: XCTestCase {
    func testLoadAccountsMarksActiveAccountAndMergesMetadata() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeCodexPaths(fileSystem: fileSystem)
        try seedAccountFixtures(fileSystem: fileSystem, paths: paths)

        let metadataStore = AccountMetadataStore(
            fileSystem: fileSystem,
            metadataURL: URL(fileURLWithPath: "/tmp/codextoken-metadata.json")
        )
        try metadataStore.save([
            "acct-work": AccountMetadata(
                customName: "Work Account",
                remark: "Priority account",
                sortOrder: 2,
                isHidden: false
            )
        ])

        let service = AccountDiscoveryService(fileSystem: fileSystem, paths: paths, metadataStore: metadataStore)
        let accounts = try service.loadAccounts()

        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts.first(where: \.isActiveCLI)?.accountID, "acct-main")

        let work = try XCTUnwrap(accounts.first(where: { $0.accountID == "acct-work" }))
        XCTAssertEqual(work.displayName, "Work Account")
        XCTAssertEqual(work.remark, "Priority account")
    }

    func testLoadAccountsIncludesCurrentSessionWhenAuthFileNotMirroredInAccountsDirectory() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeCodexPaths(fileSystem: fileSystem)

        try fileSystem.createDirectory(at: paths.codexDirectory, withIntermediateDirectories: true)
        try fileSystem.createDirectory(at: paths.accountsDirectory, withIntermediateDirectories: true)
        try fileSystem.write(
            Data(authFixture(accountID: "acct-live", lastRefresh: "2026-03-09T08:00:00Z").utf8),
            to: paths.activeAuthFile,
            options: .atomic
        )
        try fileSystem.write(
            Data(authFixture(accountID: "acct-archived", lastRefresh: "2026-03-08T08:00:00Z").utf8),
            to: paths.accountsDirectory.appendingPathComponent("acct-archived.json"),
            options: .atomic
        )

        let service = AccountDiscoveryService(
            fileSystem: fileSystem,
            paths: paths,
            metadataStore: AccountMetadataStore(
                fileSystem: fileSystem,
                metadataURL: URL(fileURLWithPath: "/tmp/codextoken-metadata.json")
            )
        )

        let accounts = try service.loadAccounts()

        XCTAssertEqual(Set(accounts.compactMap(\.accountID)), ["acct-live", "acct-archived"])
        XCTAssertTrue(accounts.contains(where: { $0.accountID == "acct-live" && $0.isImportedFromActiveSession }))
    }

    func testLoadAccountsUsesEmailFromIDTokenWhenNoCustomNameExists() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeCodexPaths(fileSystem: fileSystem)

        try fileSystem.createDirectory(at: paths.codexDirectory, withIntermediateDirectories: true)
        try fileSystem.createDirectory(at: paths.accountsDirectory, withIntermediateDirectories: true)
        try fileSystem.write(
            Data(authFixture(
                accountID: "acct-email",
                lastRefresh: "2026-03-09T08:00:00Z",
                idToken: makeIDToken(email: "person@example.com")
            ).utf8),
            to: paths.accountsDirectory.appendingPathComponent("acct-email.json"),
            options: .atomic
        )

        let service = AccountDiscoveryService(
            fileSystem: fileSystem,
            paths: paths,
            metadataStore: AccountMetadataStore(
                fileSystem: fileSystem,
                metadataURL: URL(fileURLWithPath: "/tmp/codextoken-metadata.json")
            )
        )

        let accounts = try service.loadAccounts()
        let account = try XCTUnwrap(accounts.first)

        XCTAssertEqual(account.email, "person@example.com")
        XCTAssertEqual(account.displayName, "person@example.com")
    }

    func testLoadAccountsRespectsStoredSortOrderBeforeDefaultSorting() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeCodexPaths(fileSystem: fileSystem)
        try seedAccountFixtures(fileSystem: fileSystem, paths: paths)

        let metadataStore = AccountMetadataStore(
            fileSystem: fileSystem,
            metadataURL: URL(fileURLWithPath: "/tmp/codextoken-metadata.json")
        )
        try metadataStore.save([
            "acct-work": AccountMetadata(sortOrder: 0),
            "acct-main": AccountMetadata(sortOrder: 1)
        ])

        let service = AccountDiscoveryService(fileSystem: fileSystem, paths: paths, metadataStore: metadataStore)
        let accounts = try service.loadAccounts()

        XCTAssertEqual(accounts.map(\.storageKey), ["acct-work", "acct-main"])
    }

    func testLoadAccountsReflectsLatestPersistedSortOrderAcrossRepeatedRewrites() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeCodexPaths(fileSystem: fileSystem)
        try seedAccountFixtures(fileSystem: fileSystem, paths: paths)

        let metadataStore = AccountMetadataStore(
            fileSystem: fileSystem,
            metadataURL: URL(fileURLWithPath: "/tmp/codextoken-metadata.json")
        )
        try metadataStore.save([
            "acct-main": AccountMetadata(sortOrder: 2),
            "acct-work": AccountMetadata(sortOrder: 0)
        ])

        try metadataStore.save([
            "acct-main": AccountMetadata(sortOrder: 0),
            "acct-work": AccountMetadata(sortOrder: 1)
        ])

        let service = AccountDiscoveryService(fileSystem: fileSystem, paths: paths, metadataStore: metadataStore)
        let accounts = try service.loadAccounts()

        XCTAssertEqual(accounts.map(\.storageKey), ["acct-main", "acct-work"])
    }

    func testLoadAccountsDeduplicatesSnapshotsWithSameStorageKey() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeCodexPaths(fileSystem: fileSystem)
        try fileSystem.createDirectory(at: paths.codexDirectory, withIntermediateDirectories: true)
        try fileSystem.createDirectory(at: paths.accountsDirectory, withIntermediateDirectories: true)

        try fileSystem.write(
            Data(authFixture(accountID: "acct-main", lastRefresh: "2026-03-09T10:00:00Z").utf8),
            to: paths.accountsDirectory.appendingPathComponent("acct-main-old.json"),
            options: .atomic
        )
        try fileSystem.write(
            Data(authFixture(accountID: "acct-main", lastRefresh: "2026-03-09T12:00:00Z").utf8),
            to: paths.accountsDirectory.appendingPathComponent("acct-main-new.json"),
            options: .atomic
        )

        let service = AccountDiscoveryService(
            fileSystem: fileSystem,
            paths: paths,
            metadataStore: AccountMetadataStore(
                fileSystem: fileSystem,
                metadataURL: URL(fileURLWithPath: "/tmp/codextoken-metadata.json")
            )
        )

        let accounts = try service.loadAccounts()

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.storageKey, "acct-main")
        XCTAssertEqual(accounts.first?.lastRefreshAt, ISO8601DateFormatter().date(from: "2026-03-09T12:00:00Z"))
    }
}

private func makeCodexPaths(fileSystem: InMemoryFileSystem) throws -> CodexPaths {
    try fileSystem.createDirectory(at: URL(fileURLWithPath: "/mock"), withIntermediateDirectories: true)
    return CodexPaths(baseDirectory: URL(fileURLWithPath: "/mock/.codex"))
}

private func seedAccountFixtures(fileSystem: InMemoryFileSystem, paths: CodexPaths) throws {
    try fileSystem.createDirectory(at: paths.codexDirectory, withIntermediateDirectories: true)
    try fileSystem.createDirectory(at: paths.accountsDirectory, withIntermediateDirectories: true)
    try fileSystem.write(
        Data(authFixture(accountID: "acct-main", lastRefresh: "2026-03-09T10:00:00Z").utf8),
        to: paths.activeAuthFile,
        options: .atomic
    )
    try fileSystem.write(
        Data(authFixture(accountID: "acct-main", lastRefresh: "2026-03-09T10:00:00Z").utf8),
        to: paths.accountsDirectory.appendingPathComponent("acct-main.json"),
        options: .atomic
    )
    try fileSystem.write(
        Data(authFixture(accountID: "acct-work", lastRefresh: "2026-03-08T10:00:00Z").utf8),
        to: paths.accountsDirectory.appendingPathComponent("acct-work.json"),
        options: .atomic
    )
}

private func authFixture(accountID: String, lastRefresh: String, idToken: String? = nil) -> String {
    """
    {
      "OPENAI_API_KEY": null,
      "auth_mode": "chatgpt",
      "last_refresh": "\(lastRefresh)",
      "tokens": {
        "access_token": "access-\(accountID)",
        "account_id": "\(accountID)",
        "id_token": "\(idToken ?? "id-\(accountID)")",
        "refresh_token": "refresh-\(accountID)"
      }
    }
    """
}

private func makeIDToken(email: String) -> String {
    let header = ["alg": "none", "typ": "JWT"]
    let payload = ["email": email]
    return "\(base64URL(header)).\(base64URL(payload)).signature"
}

private func base64URL(_ object: [String: String]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object)
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
