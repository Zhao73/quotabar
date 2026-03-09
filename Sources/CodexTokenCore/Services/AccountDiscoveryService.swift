import Foundation

public final class AccountDiscoveryService {
    private let fileSystem: any FileSystem
    private let paths: CodexPaths
    private let metadataStore: AccountMetadataStore
    private let decoder = JSONDecoder()
    private let iso8601Formatter = ISO8601DateFormatter()

    public init(
        fileSystem: any FileSystem = LocalFileSystem(),
        paths: CodexPaths = .live(),
        metadataStore: AccountMetadataStore
    ) {
        self.fileSystem = fileSystem
        self.paths = paths
        self.metadataStore = metadataStore
    }

    public func loadAccounts() throws -> [CodexAccount] {
        let metadata = try metadataStore.load()
        let activeRecord = try loadAuthRecord(from: paths.activeAuthFile)
        let accountFiles = (try? fileSystem.contentsOfDirectory(at: paths.accountsDirectory)) ?? []
            .filter { $0.pathExtension.lowercased() == "json" }

        var accountsByStorageKey: [String: CodexAccount] = [:]
        var seenStorageKeys = Set<String>()

        for file in accountFiles {
            guard let record = try loadAuthRecord(from: file) else { continue }
            let storageKey = Self.storageKey(for: record, fallbackURL: file)
            let merged = buildAccount(
                record: record,
                storageKey: storageKey,
                sourceFile: file,
                metadata: metadata[storageKey],
                isImportedFromActiveSession: false,
                activeRecord: activeRecord
            )
            seenStorageKeys.insert(storageKey)
            if !(metadata[storageKey]?.isHidden ?? false) {
                accountsByStorageKey[storageKey] = Self.preferredAccount(
                    current: accountsByStorageKey[storageKey],
                    candidate: merged
                )
            }
        }

        if let activeRecord {
            let activeStorageKey = Self.storageKey(for: activeRecord, fallbackURL: paths.activeAuthFile)
            if !seenStorageKeys.contains(activeStorageKey) {
                let account = buildAccount(
                    record: activeRecord,
                    storageKey: activeStorageKey,
                    sourceFile: paths.activeAuthFile,
                    metadata: metadata[activeStorageKey],
                    isImportedFromActiveSession: true,
                    activeRecord: activeRecord
                )
                if !(metadata[activeStorageKey]?.isHidden ?? false) {
                    accountsByStorageKey[activeStorageKey] = Self.preferredAccount(
                        current: accountsByStorageKey[activeStorageKey],
                        candidate: account
                    )
                }
            }
        }

        return Array(accountsByStorageKey.values).sorted(by: Self.sortAccounts)
    }

    private func loadAuthRecord(from url: URL) throws -> AuthRecord? {
        guard fileSystem.fileExists(at: url) else { return nil }
        let data = try fileSystem.read(from: url)
        return try decoder.decode(AuthRecord.self, from: data)
    }

    private func buildAccount(
        record: AuthRecord,
        storageKey: String,
        sourceFile: URL?,
        metadata: AccountMetadata?,
        isImportedFromActiveSession: Bool,
        activeRecord: AuthRecord?
    ) -> CodexAccount {
        let fallbackName = record.tokens.email
            ?? record.tokens.accountID
            ?? sourceFile?.deletingPathExtension().lastPathComponent
            ?? "Unknown"

        return CodexAccount(
            id: storageKey,
            storageKey: storageKey,
            sourceFile: sourceFile,
            accountID: record.tokens.accountID,
            email: record.tokens.email,
            loginProvider: record.tokens.authProvider,
            sortOrder: metadata?.sortOrder ?? 0,
            displayName: metadata?.customName ?? fallbackName,
            remark: metadata?.remark,
            authMode: CodexAuthMode(rawValue: record.authMode),
            lastRefreshAt: record.lastRefreshDate(using: iso8601Formatter),
            isActiveCLI: Self.matchesActiveRecord(record, activeRecord: activeRecord),
            isImportedFromActiveSession: isImportedFromActiveSession
        )
    }

    private static func storageKey(for record: AuthRecord, fallbackURL: URL) -> String {
        record.tokens.accountID ?? fallbackURL.deletingPathExtension().lastPathComponent
    }

    private static func matchesActiveRecord(_ record: AuthRecord, activeRecord: AuthRecord?) -> Bool {
        guard let activeRecord else { return false }
        if let lhs = record.tokens.accountID, let rhs = activeRecord.tokens.accountID {
            return lhs == rhs
        }
        return record.lastRefresh == activeRecord.lastRefresh
    }

    private static func sortAccounts(lhs: CodexAccount, rhs: CodexAccount) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.isActiveCLI != rhs.isActiveCLI {
            return lhs.isActiveCLI && !rhs.isActiveCLI
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func preferredAccount(current: CodexAccount?, candidate: CodexAccount) -> CodexAccount {
        guard let current else { return candidate }
        switch (current.lastRefreshAt, candidate.lastRefreshAt) {
        case let (lhs?, rhs?) where rhs > lhs:
            return candidate
        case let (lhs?, rhs?) where rhs < lhs:
            return current
        case (nil, _?):
            return candidate
        default:
            if candidate.isActiveCLI && !current.isActiveCLI {
                return candidate
            }
            return current
        }
    }
}

private struct AuthRecord: Decodable {
    struct Tokens: Decodable {
        let accountID: String?
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accountID = "account_id"
            case idToken = "id_token"
        }

        var email: String? {
            claims?["email"] as? String
        }

        var authProvider: String? {
            claims?["auth_provider"] as? String
        }

        private var claims: [String: Any]? {
            guard let idToken else { return nil }
            return Self.decodeClaims(from: idToken)
        }

        private static func decodeClaims(from jwt: String) -> [String: Any]? {
            let segments = jwt.split(separator: ".")
            guard segments.count >= 2 else { return nil }

            var payload = String(segments[1])
            let remainder = payload.count % 4
            if remainder != 0 {
                payload += String(repeating: "=", count: 4 - remainder)
            }

            guard let data = Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }

            return json
        }
    }

    let authMode: String?
    let lastRefresh: String?
    let tokens: Tokens

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case lastRefresh = "last_refresh"
        case tokens
    }

    func lastRefreshDate(using formatter: ISO8601DateFormatter) -> Date? {
        guard let lastRefresh else { return nil }
        return formatter.date(from: lastRefresh)
    }
}
