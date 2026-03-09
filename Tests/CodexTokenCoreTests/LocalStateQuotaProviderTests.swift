import XCTest
@testable import CodexTokenCore

final class LocalStateQuotaProviderTests: XCTestCase {
    func testLocalStateProviderReturnsUnknownQuotaWithStableMetadata() async throws {
        let account = CodexAccount(
            id: "acct-main",
            storageKey: "acct-main",
            sourceFile: URL(fileURLWithPath: "/mock/.codex/accounts/acct-main.json"),
            accountID: "acct-main",
            displayName: "Main",
            remark: "Personal",
            authMode: .chatGPT,
            lastRefreshAt: ISO8601DateFormatter().date(from: "2026-03-09T10:00:00Z"),
            isActiveCLI: true,
            isImportedFromActiveSession: false
        )

        let snapshot = await LocalStateQuotaProvider().snapshot(for: account)

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertEqual(snapshot.sourceLabel, "Local Codex state")
        XCTAssertEqual(snapshot.confidence, .high)
        XCTAssertEqual(snapshot.refreshedAt, account.lastRefreshAt)
        XCTAssertTrue(snapshot.warnings.contains("No official quota source configured."))
    }

    func testCompositeQuotaProviderFallsBackToLocalProvider() async throws {
        let account = CodexAccount(
            id: "acct-main",
            storageKey: "acct-main",
            sourceFile: nil,
            accountID: "acct-main",
            displayName: "Main",
            remark: nil,
            authMode: .chatGPT,
            lastRefreshAt: nil,
            isActiveCLI: false,
            isImportedFromActiveSession: false
        )

        let composite = CompositeQuotaProvider(
            primary: ExperimentalQuotaProvider(configuration: .disabled),
            fallback: LocalStateQuotaProvider()
        )

        let snapshot = await composite.snapshot(for: account)

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertEqual(snapshot.sourceLabel, "Local Codex state")
    }
}

