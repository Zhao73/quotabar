import Foundation

public struct CodexPaths: Equatable, Sendable {
    public let baseDirectory: URL
    public let codexDirectory: URL
    public let activeAuthFile: URL
    public let accountsDirectory: URL
    public let configFile: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        self.codexDirectory = baseDirectory
        self.activeAuthFile = baseDirectory.appendingPathComponent("auth.json")
        self.accountsDirectory = baseDirectory.appendingPathComponent("accounts")
        self.configFile = baseDirectory.appendingPathComponent("config.toml")
    }

    public static func live(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> CodexPaths {
        CodexPaths(baseDirectory: homeDirectory.appendingPathComponent(".codex"))
    }
}

