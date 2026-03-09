import XCTest
@testable import CodexTokenCore

final class CodexAppServerQuotaProviderTests: XCTestCase {
    func testProviderMapsPrimaryAndSecondaryRateLimitWindows() async {
        let provider = CodexAppServerQuotaProvider(
            reader: MockCodexAppServerRateLimitReader(
                response: CodexAppServerRateLimitsResponse(
                    rateLimits: .init(
                        credits: .init(balance: "0", hasCredits: false, unlimited: false),
                        limitId: "codex",
                        limitName: "Codex",
                        planType: "plus",
                        primary: .init(resetsAt: 1_773_001_042, usedPercent: 53, windowDurationMins: 300),
                        secondary: .init(resetsAt: 1_773_587_842, usedPercent: 16, windowDurationMins: 10_080)
                    ),
                    rateLimitsByLimitId: nil
                )
            )
        )

        let snapshot = await provider.snapshot(for: makeAccount())

        XCTAssertEqual(snapshot.status, .experimental)
        XCTAssertEqual(snapshot.sourceLabel, "Codex app-server")
        XCTAssertEqual(snapshot.primaryWindow?.usedPercent, 53)
        XCTAssertEqual(snapshot.primaryWindow?.windowDurationMinutes, 300)
        XCTAssertEqual(snapshot.secondaryWindow?.usedPercent, 16)
        XCTAssertEqual(snapshot.secondaryWindow?.windowDurationMinutes, 10_080)
        XCTAssertTrue(snapshot.warnings.contains("Plan: plus"))
    }

    func testProviderReturnsErrorSnapshotWhenReaderFails() async {
        let provider = CodexAppServerQuotaProvider(
            reader: MockCodexAppServerRateLimitReader(
                response: nil,
                error: CodexAppServerRateLimitError.timedOut
            )
        )

        let snapshot = await provider.snapshot(for: makeAccount())

        XCTAssertEqual(snapshot.status, .error)
        XCTAssertEqual(snapshot.sourceLabel, "Codex app-server")
        XCTAssertEqual(snapshot.errorDescription, CodexAppServerRateLimitError.timedOut.localizedDescription)
    }
}

private struct MockCodexAppServerRateLimitReader: CodexAppServerRateLimitReading {
    let response: CodexAppServerRateLimitsResponse?
    var error: Error?

    func readRateLimits(codexHomeDirectory: URL?) async throws -> CodexAppServerRateLimitsResponse {
        if let error {
            throw error
        }
        return response!
    }
}

private func makeAccount() -> CodexAccount {
    CodexAccount(
        id: "acct-main",
        storageKey: "acct-main",
        sourceFile: nil,
        accountID: "acct-main",
        email: "person@example.com",
        displayName: "person@example.com",
        remark: nil,
        authMode: .chatGPT,
        lastRefreshAt: nil,
        isActiveCLI: true,
        isImportedFromActiveSession: false
    )
}
