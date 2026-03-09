import XCTest
@testable import CodexTokenCore

final class CLIProfilePreparationServiceTests: XCTestCase {
    func testPrepareProfileCopiesSelectedAccountIntoIsolatedCodexHome() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeProfilePaths(fileSystem: fileSystem)
        let profileRoot = URL(fileURLWithPath: "/tmp/codextoken-cli-profiles")
        let sourceFile = paths.accountsDirectory.appendingPathComponent("acct-work.json")

        try fileSystem.write(
            Data(authFixture(accountID: "acct-work").utf8),
            to: sourceFile,
            options: .atomic
        )
        try fileSystem.write(
            Data("model = \"gpt-5\"\n".utf8),
            to: paths.configFile,
            options: .atomic
        )

        let service = CLIProfilePreparationService(
            fileSystem: fileSystem,
            globalPaths: paths,
            profileRootDirectory: profileRoot
        )

        let profile = try service.prepareProfile(
            for: CodexAccount(
                id: "acct-work",
                storageKey: "acct-work",
                sourceFile: sourceFile,
                accountID: "acct-work",
                email: "work@example.com",
                loginProvider: "password",
                displayName: "work@example.com",
                remark: nil,
                authMode: .chatGPT,
                lastRefreshAt: nil,
                isActiveCLI: false,
                isImportedFromActiveSession: false
            )
        )

        XCTAssertEqual(profile.codexHomeDirectory.path, "/tmp/codextoken-cli-profiles/acct-work/.codex")
        XCTAssertTrue(fileSystem.fileExists(at: profile.authFile))
        XCTAssertTrue(fileSystem.fileExists(at: profile.snapshotFile))
        XCTAssertTrue(fileSystem.fileExists(at: profile.configFile))

        let authData = try fileSystem.read(from: profile.authFile)
        XCTAssertTrue(String(decoding: authData, as: UTF8.self).contains("\"account_id\": \"acct-work\""))
    }

    func testPrepareProfileThrowsWhenBackingAuthSnapshotIsMissing() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeProfilePaths(fileSystem: fileSystem)

        let service = CLIProfilePreparationService(
            fileSystem: fileSystem,
            globalPaths: paths,
            profileRootDirectory: URL(fileURLWithPath: "/tmp/codextoken-cli-profiles")
        )

        XCTAssertThrowsError(
            try service.prepareProfile(
                for: CodexAccount(
                    id: "acct-missing",
                    storageKey: "acct-missing",
                    sourceFile: paths.accountsDirectory.appendingPathComponent("acct-missing.json"),
                    accountID: "acct-missing",
                    email: nil,
                    loginProvider: nil,
                    displayName: "acct-missing",
                    remark: nil,
                    authMode: .chatGPT,
                    lastRefreshAt: nil,
                    isActiveCLI: false,
                    isImportedFromActiveSession: false
                )
            )
        )
    }
}

private func makeProfilePaths(fileSystem: InMemoryFileSystem) throws -> CodexPaths {
    let codexDirectory = URL(fileURLWithPath: "/mock/.codex")
    try fileSystem.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
    try fileSystem.createDirectory(at: codexDirectory.appendingPathComponent("accounts"), withIntermediateDirectories: true)
    return CodexPaths(baseDirectory: codexDirectory)
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
