import XCTest
@testable import CodexTokenCore

final class AccountSnapshotImportServiceTests: XCTestCase {
    func testImportCurrentSessionCopiesActiveAuthIntoAccountsDirectory() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makePaths(fileSystem: fileSystem)
        try fileSystem.write(
            Data(authFixture(accountID: "acct-import").utf8),
            to: paths.activeAuthFile,
            options: .atomic
        )

        let service = AccountSnapshotImportService(fileSystem: fileSystem, paths: paths)
        let destination = try service.importCurrentSessionSnapshot(preferredFileName: nil)

        XCTAssertEqual(destination.lastPathComponent, "acct-import.json")
        let copied = try fileSystem.read(from: destination)
        XCTAssertTrue(String(decoding: copied, as: UTF8.self).contains("\"account_id\": \"acct-import\""))
    }

    func testStoreSnapshotCopiesArbitraryAuthFileIntoAccountsDirectory() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makePaths(fileSystem: fileSystem)
        let source = URL(fileURLWithPath: "/tmp/new-auth.json")
        try fileSystem.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileSystem.write(
            Data(authFixture(accountID: "acct-stored").utf8),
            to: source,
            options: .atomic
        )

        let service = AccountSnapshotImportService(fileSystem: fileSystem, paths: paths)
        let destination = try service.storeSnapshot(from: source, preferredFileName: "saved-account")

        XCTAssertEqual(destination.lastPathComponent, "saved-account.json")
        let copied = try fileSystem.read(from: destination)
        XCTAssertTrue(String(decoding: copied, as: UTF8.self).contains("\"account_id\": \"acct-stored\""))
    }
}

private func makePaths(fileSystem: InMemoryFileSystem) throws -> CodexPaths {
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
