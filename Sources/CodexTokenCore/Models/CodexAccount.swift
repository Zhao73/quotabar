import Foundation

public enum CodexAuthMode: String, Codable, Sendable {
    case chatGPT = "chatgpt"
    case apiKey = "api_key"
    case unknown

    init(rawValue: String?) {
        switch rawValue?.lowercased() {
        case "chatgpt":
            self = .chatGPT
        case "api_key":
            self = .apiKey
        default:
            self = .unknown
        }
    }
}

public struct CodexAccount: Identifiable, Equatable, Sendable {
    public let id: String
    public let storageKey: String
    public let sourceFile: URL?
    public let accountID: String?
    public let email: String?
    public let loginProvider: String?
    public let sortOrder: Int
    public let displayName: String
    public let remark: String?
    public let authMode: CodexAuthMode
    public let lastRefreshAt: Date?
    public let isActiveCLI: Bool
    public let isImportedFromActiveSession: Bool

    public init(
        id: String,
        storageKey: String,
        sourceFile: URL?,
        accountID: String?,
        email: String? = nil,
        loginProvider: String? = nil,
        sortOrder: Int = 0,
        displayName: String,
        remark: String?,
        authMode: CodexAuthMode,
        lastRefreshAt: Date?,
        isActiveCLI: Bool,
        isImportedFromActiveSession: Bool
    ) {
        self.id = id
        self.storageKey = storageKey
        self.sourceFile = sourceFile
        self.accountID = accountID
        self.email = email
        self.loginProvider = loginProvider
        self.sortOrder = sortOrder
        self.displayName = displayName
        self.remark = remark
        self.authMode = authMode
        self.lastRefreshAt = lastRefreshAt
        self.isActiveCLI = isActiveCLI
        self.isImportedFromActiveSession = isImportedFromActiveSession
    }
}
