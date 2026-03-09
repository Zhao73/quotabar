import Foundation

public struct CLIProfileLaunchContext: Equatable, Sendable {
    public let storageKey: String
    public let codexHomeDirectory: URL
    public let authFile: URL
    public let snapshotFile: URL
    public let configFile: URL

    public init(
        storageKey: String,
        codexHomeDirectory: URL,
        authFile: URL,
        snapshotFile: URL,
        configFile: URL
    ) {
        self.storageKey = storageKey
        self.codexHomeDirectory = codexHomeDirectory
        self.authFile = authFile
        self.snapshotFile = snapshotFile
        self.configFile = configFile
    }
}

public enum CLIProfilePreparationError: LocalizedError {
    case missingSourceFile
    case sourceSnapshotMissing(URL)

    public var errorDescription: String? {
        switch self {
        case .missingSourceFile:
            return "The selected account does not have a backing auth snapshot."
        case let .sourceSnapshotMissing(url):
            return "The selected account snapshot could not be found at \(url.path)."
        }
    }
}

public final class CLIProfilePreparationService {
    private let fileSystem: any FileSystem
    private let globalPaths: CodexPaths
    private let profileRootDirectory: URL

    public init(
        fileSystem: any FileSystem = LocalFileSystem(),
        globalPaths: CodexPaths = .live(),
        profileRootDirectory: URL
    ) {
        self.fileSystem = fileSystem
        self.globalPaths = globalPaths
        self.profileRootDirectory = profileRootDirectory
    }

    public func prepareProfile(for account: CodexAccount) throws -> CLIProfileLaunchContext {
        guard let sourceFile = account.sourceFile else {
            throw CLIProfilePreparationError.missingSourceFile
        }
        guard fileSystem.fileExists(at: sourceFile) else {
            throw CLIProfilePreparationError.sourceSnapshotMissing(sourceFile)
        }

        let codexHomeDirectory = profileRootDirectory
            .appendingPathComponent(account.storageKey)
            .appendingPathComponent(".codex", isDirectory: true)
        let accountsDirectory = codexHomeDirectory.appendingPathComponent("accounts", isDirectory: true)
        let authFile = codexHomeDirectory.appendingPathComponent("auth.json")
        let snapshotFile = accountsDirectory.appendingPathComponent(sourceFile.lastPathComponent)
        let configFile = codexHomeDirectory.appendingPathComponent("config.toml")

        try fileSystem.createDirectory(at: codexHomeDirectory, withIntermediateDirectories: true)
        try fileSystem.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)

        let authData = try fileSystem.read(from: sourceFile)
        try fileSystem.write(authData, to: authFile, options: .atomic)
        try fileSystem.write(authData, to: snapshotFile, options: .atomic)

        if fileSystem.fileExists(at: globalPaths.configFile) {
            let configData = try fileSystem.read(from: globalPaths.configFile)
            try fileSystem.write(configData, to: configFile, options: .atomic)
        }

        return CLIProfileLaunchContext(
            storageKey: account.storageKey,
            codexHomeDirectory: codexHomeDirectory,
            authFile: authFile,
            snapshotFile: snapshotFile,
            configFile: configFile
        )
    }
}
