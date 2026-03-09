import Foundation

public final class AccountMetadataStore {
    private let fileSystem: any FileSystem
    private let metadataURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileSystem: any FileSystem = LocalFileSystem(), metadataURL: URL) {
        self.fileSystem = fileSystem
        self.metadataURL = metadataURL
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> [String: AccountMetadata] {
        guard fileSystem.fileExists(at: metadataURL) else {
            return [:]
        }

        let data = try fileSystem.read(from: metadataURL)
        return try decoder.decode([String: AccountMetadata].self, from: data)
    }

    public func save(_ metadata: [String: AccountMetadata]) throws {
        let data = try encoder.encode(metadata)
        try fileSystem.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileSystem.write(data, to: metadataURL, options: .atomic)
    }

    public func upsert(metadata: AccountMetadata, for storageKey: String) throws {
        var existing = try load()
        existing[storageKey] = metadata
        try save(existing)
    }
}
