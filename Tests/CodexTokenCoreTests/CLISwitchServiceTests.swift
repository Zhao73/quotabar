import XCTest
@testable import CodexTokenCore

final class CLISwitchServiceTests: XCTestCase {
    func testSwitchToAccountReplacesActiveAuthFile() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makePaths(fileSystem: fileSystem)
        try fileSystem.write(
            Data(authFixture(accountID: "acct-main").utf8),
            to: paths.activeAuthFile,
            options: .atomic
        )

        let sourceURL = paths.accountsDirectory.appendingPathComponent("acct-work.json")
        try fileSystem.write(
            Data(authFixture(accountID: "acct-work").utf8),
            to: sourceURL,
            options: .atomic
        )

        let service = CLISwitchService(
            fileSystem: fileSystem,
            paths: paths,
            validator: MockCLIStatusValidating(result: .success)
        )

        _ = try service.switchToAccount(
            CodexAccount(
                id: "acct-work",
                storageKey: "acct-work",
                sourceFile: sourceURL,
                accountID: "acct-work",
                displayName: "Work",
                remark: nil,
                authMode: .chatGPT,
                lastRefreshAt: nil,
                isActiveCLI: false,
                isImportedFromActiveSession: false
            )
        )

        let data = try fileSystem.read(from: paths.activeAuthFile)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"account_id\": \"acct-work\""))
    }

    func testSwitchRollsBackWhenValidationFails() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makePaths(fileSystem: fileSystem)
        try fileSystem.write(
            Data(authFixture(accountID: "acct-main").utf8),
            to: paths.activeAuthFile,
            options: .atomic
        )

        let sourceURL = paths.accountsDirectory.appendingPathComponent("acct-work.json")
        try fileSystem.write(
            Data(authFixture(accountID: "acct-work").utf8),
            to: sourceURL,
            options: .atomic
        )

        let service = CLISwitchService(
            fileSystem: fileSystem,
            paths: paths,
            validator: MockCLIStatusValidating(result: .failure("validation failed"))
        )

        XCTAssertThrowsError(
            try service.switchToAccount(
                CodexAccount(
                    id: "acct-work",
                    storageKey: "acct-work",
                    sourceFile: sourceURL,
                    accountID: "acct-work",
                    displayName: "Work",
                    remark: nil,
                    authMode: .chatGPT,
                    lastRefreshAt: nil,
                    isActiveCLI: false,
                    isImportedFromActiveSession: false
                )
            )
        )

        let data = try fileSystem.read(from: paths.activeAuthFile)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"account_id\": \"acct-main\""))
    }
}

private func makePaths(fileSystem: InMemoryFileSystem) throws -> CodexPaths {
    let codexDirectory = URL(fileURLWithPath: "/mock/.codex")
    try fileSystem.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
    try fileSystem.createDirectory(at: codexDirectory.appendingPathComponent("accounts"), withIntermediateDirectories: true)
    return CodexPaths(baseDirectory: codexDirectory)
}

private struct MockCLIStatusValidating: CLIStatusValidating {
    let result: CLIValidationResult

    func validateCurrentLogin() -> CLIValidationResult {
        result
    }
}

private func authFixture(accountID: String) -> String {
    """
    {
      "OPENAI_API_KEY": null,
      "auth_mode": "chatgpt",
      "last_refresh": "2026-03-09T08:00:00Z",
      "tokens": {
        "access_token": "access-\(accountID)",
        "account_id": "\(accountID)",
        "id_token": "id-\(accountID)",
        "refresh_token": "refresh-\(accountID)"
      }
    }
    """
}
