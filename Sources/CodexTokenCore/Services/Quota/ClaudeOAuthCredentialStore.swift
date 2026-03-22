import Foundation

public protocol ClaudeOAuthCredentialReading: Sendable {
    func readCredentialData() throws -> Data
}

public struct ClaudeOAuthCredentialStore: Sendable {
    private let reader: any ClaudeOAuthCredentialReading

    public init(reader: any ClaudeOAuthCredentialReading = DefaultReader()) {
        self.reader = reader
    }

    public func load() throws -> ClaudeOAuthCredentials {
        let data = try reader.readCredentialData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(ClaudeOAuthCredentials.self, from: data)
    }

    public struct DefaultReader: ClaudeOAuthCredentialReading, Sendable {
        public init() {}
        private static var credentialURL: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent(".credentials.json")
        }

        public func readCredentialData() throws -> Data {
            try Data(contentsOf: Self.credentialURL)
        }
    }

    public struct StaticReader: ClaudeOAuthCredentialReading, Sendable {
        private let data: Data?
        private let errorDescription: String?

        public init(data: Data) {
            self.data = data
            self.errorDescription = nil
        }

        public init(error: Error) {
            self.data = nil
            self.errorDescription = error.localizedDescription
        }

        public func readCredentialData() throws -> Data {
            if let errorDescription {
                throw NSError(
                    domain: "ClaudeOAuthCredentialStore.StaticReader",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: errorDescription]
                )
            }
            return data!
        }
    }
}

public struct ClaudeOAuthCredentials: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scopes: [String]
    public let rateLimitTier: String?

    enum CodingKeys: String, CodingKey {
        case claudeAiOauth
    }

    enum OAuthKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresAt
        case scopes
        case rateLimitTier
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    public var expiresInMinutes: Int? {
        guard let expiresAt else { return nil }
        let interval = expiresAt.timeIntervalSince(Date())
        guard interval > 0 else { return 0 }
        return Int(interval / 60)
    }

    public var isExpiringSoon: Bool {
        guard let minutes = expiresInMinutes else { return false }
        return minutes > 0 && minutes <= 30
    }

    public init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        scopes: [String],
        rateLimitTier: String?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.rateLimitTier = rateLimitTier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let oauth = try container.nestedContainer(keyedBy: OAuthKeys.self, forKey: .claudeAiOauth)
        let accessToken = try oauth.decode(String.self, forKey: .accessToken)
        let refreshToken = try oauth.decodeIfPresent(String.self, forKey: .refreshToken)
        let expiresAtMs = try oauth.decodeIfPresent(Double.self, forKey: .expiresAt)
        let expiresAt = expiresAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) }
        let scopes = try oauth.decodeIfPresent([String].self, forKey: .scopes) ?? []
        let rateLimitTier = try oauth.decodeIfPresent(String.self, forKey: .rateLimitTier)
        self.init(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scopes: scopes,
            rateLimitTier: rateLimitTier
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var oauth = container.nestedContainer(keyedBy: OAuthKeys.self, forKey: .claudeAiOauth)
        try oauth.encode(accessToken, forKey: .accessToken)
        try oauth.encodeIfPresent(refreshToken, forKey: .refreshToken)
        if let expiresAt {
            try oauth.encode(expiresAt.timeIntervalSince1970 * 1000.0, forKey: .expiresAt)
        }
        try oauth.encode(scopes, forKey: .scopes)
        try oauth.encodeIfPresent(rateLimitTier, forKey: .rateLimitTier)
    }
}

extension ClaudeOAuthCredentialStore {
    @available(*, deprecated, message: "Use staticStore instead.")
    public static func StaticStore(
        credentials: ClaudeOAuthCredentials? = nil,
        error: Error? = nil
    ) -> ClaudeOAuthCredentialStore {
        staticStore(credentials: credentials, error: error)
    }

    public static func staticStore(
        credentials: ClaudeOAuthCredentials? = nil,
        error: Error? = nil
    ) -> ClaudeOAuthCredentialStore {
        let reader: ClaudeOAuthCredentialReading
        if let error {
            reader = StaticReader(error: error)
        } else if let credentials {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try! encoder.encode(CredentialEnvelope(oauth: credentials))
            reader = StaticReader(data: data)
        } else {
            reader = StaticReader(error: NSError(domain: "claude", code: 42, userInfo: nil))
        }
        return ClaudeOAuthCredentialStore(reader: reader)
    }

    public static func staticStore(errorDescription: String) -> ClaudeOAuthCredentialStore {
        ClaudeOAuthCredentialStore(
            reader: StaticReader(
                error: NSError(
                    domain: "ClaudeOAuthCredentialStore.StaticReader",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: errorDescription]
                )
            )
        )
    }

    private struct CredentialEnvelope: Encodable {
        let claudeAiOauth: OAuthPayload

        init(oauth: ClaudeOAuthCredentials) {
            self.claudeAiOauth = OAuthPayload(
                accessToken: oauth.accessToken,
                refreshToken: oauth.refreshToken,
                expiresAt: oauth.expiresAt.map { $0.timeIntervalSince1970 * 1000.0 },
                scopes: oauth.scopes,
                rateLimitTier: oauth.rateLimitTier
            )
        }
    }

    private struct OAuthPayload: Encodable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Double?
        let scopes: [String]
        let rateLimitTier: String?
    }
}
