import Foundation

public enum AccountSnapshotImportError: LocalizedError {
    case activeAuthMissing
    case unreadableAccountIdentifier

    public var errorDescription: String? {
        switch self {
        case .activeAuthMissing:
            return "The active Codex auth.json file could not be found."
        case .unreadableAccountIdentifier:
            return "The current auth.json session does not contain a usable account identifier."
        }
    }
}

public final class AccountSnapshotImportService {
    private let fileSystem: any FileSystem
    private let paths: CodexPaths
    private let decoder = JSONDecoder()

    public init(
        fileSystem: any FileSystem = LocalFileSystem(),
        paths: CodexPaths = .live()
    ) {
        self.fileSystem = fileSystem
        self.paths = paths
    }

    @discardableResult
    public func importCurrentSessionSnapshot(preferredFileName: String?) throws -> URL {
        guard fileSystem.fileExists(at: paths.activeAuthFile) else {
            throw AccountSnapshotImportError.activeAuthMissing
        }

        return try storeSnapshot(from: paths.activeAuthFile, preferredFileName: preferredFileName)
    }

    @discardableResult
    public func storeSnapshot(from sourceFile: URL, preferredFileName: String?) throws -> URL {
        guard fileSystem.fileExists(at: sourceFile) else {
            throw AccountSnapshotImportError.activeAuthMissing
        }

        let data = try fileSystem.read(from: sourceFile)
        let record = try decoder.decode(ImportedAuthRecord.self, from: data)

        let baseName = sanitizedBaseName(
            preferredFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? sanitizedBaseName(record.tokens.accountID) ?? sanitizedBaseName(record.accountID)

        guard let baseName else {
            throw AccountSnapshotImportError.unreadableAccountIdentifier
        }

        let destination = paths.accountsDirectory.appendingPathComponent("\(baseName).json")
        try fileSystem.createDirectory(at: paths.accountsDirectory, withIntermediateDirectories: true)
        try fileSystem.write(data, to: destination, options: .atomic)
        return destination
    }

    private func sanitizedBaseName(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return collapsed.isEmpty ? nil : collapsed
    }
}

private struct ImportedAuthRecord: Decodable {
    struct Tokens: Decodable {
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accountID = "account_id"
        }
    }

    let accountID: String?
    let tokens: Tokens

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case tokens
    }
}
