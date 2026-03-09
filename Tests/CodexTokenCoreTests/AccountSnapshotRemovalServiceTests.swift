import XCTest
@testable import CodexTokenCore

final class AccountSnapshotRemovalServiceTests: XCTestCase {
    func testRemoveAccountDeletesSnapshotFileAndMetadata() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeCodexPathsForRemoval(fileSystem: fileSystem)
        let metadataURL = URL(fileURLWithPath: "/tmp/codextoken-removal-metadata.json")
        let metadataStore = AccountMetadataStore(fileSystem: fileSystem, metadataURL: metadataURL)
        let sourceFile = paths.accountsDirectory.appendingPathComponent("acct-main.json")

        try fileSystem.write(Data("{}".utf8), to: sourceFile, options: .atomic)
        try metadataStore.save([
            "acct-main": AccountMetadata(remark: "duplicate", sortOrder: 1)
        ])

        let service = AccountSnapshotRemovalService(
            fileSystem: fileSystem,
            paths: paths,
            metadataStore: metadataStore
        )

        let result = try service.removeAccount(
            CodexAccount(
                id: "acct-main",
                storageKey: "acct-main",
                sourceFile: sourceFile,
                accountID: "acct-main",
                displayName: "acct-main",
                remark: nil,
                authMode: .chatGPT,
                lastRefreshAt: nil,
                isActiveCLI: false,
                isImportedFromActiveSession: false
            )
        )

        XCTAssertEqual(result, .removedSnapshot)
        XCTAssertFalse(fileSystem.fileExists(at: sourceFile))
        XCTAssertTrue((try metadataStore.load()).isEmpty)
    }

    func testRemoveCurrentSessionOnlyAccountMarksItHiddenWithoutDeletingAuthFile() throws {
        let fileSystem = InMemoryFileSystem()
        let paths = try makeCodexPathsForRemoval(fileSystem: fileSystem)
        let metadataURL = URL(fileURLWithPath: "/tmp/codextoken-removal-metadata.json")
        let metadataStore = AccountMetadataStore(fileSystem: fileSystem, metadataURL: metadataURL)

        try fileSystem.write(Data("{}".utf8), to: paths.activeAuthFile, options: .atomic)

        let service = AccountSnapshotRemovalService(
            fileSystem: fileSystem,
            paths: paths,
            metadataStore: metadataStore
        )

        let result = try service.removeAccount(
            CodexAccount(
                id: "acct-live",
                storageKey: "acct-live",
                sourceFile: paths.activeAuthFile,
                accountID: "acct-live",
                displayName: "acct-live",
                remark: nil,
                authMode: .chatGPT,
                lastRefreshAt: nil,
                isActiveCLI: true,
                isImportedFromActiveSession: true
            )
        )

        XCTAssertEqual(result, .hiddenCurrentSession)
        XCTAssertTrue(fileSystem.fileExists(at: paths.activeAuthFile))
        XCTAssertEqual((try metadataStore.load())["acct-live"]?.isHidden, true)
    }
}

private func makeCodexPathsForRemoval(fileSystem: InMemoryFileSystem) throws -> CodexPaths {
    try fileSystem.createDirectory(at: URL(fileURLWithPath: "/mock"), withIntermediateDirectories: true)
    let paths = CodexPaths(baseDirectory: URL(fileURLWithPath: "/mock/.codex"))
    try fileSystem.createDirectory(at: paths.codexDirectory, withIntermediateDirectories: true)
    try fileSystem.createDirectory(at: paths.accountsDirectory, withIntermediateDirectories: true)
    return paths
}
