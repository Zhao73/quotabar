import Foundation

public enum AccountSnapshotRemovalResult: Equatable, Sendable {
    case removedSnapshot
    case hiddenCurrentSession
}

public final class AccountSnapshotRemovalService {
    private let fileSystem: any FileSystem
    private let paths: CodexPaths
    private let metadataStore: AccountMetadataStore

    public init(
        fileSystem: any FileSystem = LocalFileSystem(),
        paths: CodexPaths = .live(),
        metadataStore: AccountMetadataStore
    ) {
        self.fileSystem = fileSystem
        self.paths = paths
        self.metadataStore = metadataStore
    }

    public func removeAccount(_ account: CodexAccount) throws -> AccountSnapshotRemovalResult {
        var metadata = try metadataStore.load()

        if let sourceFile = account.sourceFile, isSnapshotFile(sourceFile) {
            if fileSystem.fileExists(at: sourceFile) {
                try fileSystem.removeItem(at: sourceFile)
            }
            metadata.removeValue(forKey: account.storageKey)
            try metadataStore.save(metadata)
            return .removedSnapshot
        }

        var item = metadata[account.storageKey] ?? AccountMetadata()
        item.isHidden = true
        metadata[account.storageKey] = item
        try metadataStore.save(metadata)
        return .hiddenCurrentSession
    }

    private func isSnapshotFile(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path == paths.accountsDirectory.standardizedFileURL.path
    }
}
