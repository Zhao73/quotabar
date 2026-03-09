import Foundation

public enum CLIValidationResult: Equatable, Sendable {
    case success
    case failure(String)
}

public protocol CLIStatusValidating {
    func validateCurrentLogin() -> CLIValidationResult
}

public struct DefaultCLIStatusValidator: CLIStatusValidating {
    private let commandRunner: any ShellCommandRunning

    public init(commandRunner: any ShellCommandRunning = DefaultShellCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func validateCurrentLogin() -> CLIValidationResult {
        do {
            let result = try commandRunner.run(shellCommand: "codex login status")
            guard result.exitCode == 0 else {
                return .failure(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            if result.standardOutput.localizedCaseInsensitiveContains("logged in") {
                return .success
            }

            return .failure("`codex login status` did not confirm an active login.")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

public struct CLISwitchResult: Equatable, Sendable {
    public let switchedAccountID: String?
    public let validationResult: CLIValidationResult

    public init(switchedAccountID: String?, validationResult: CLIValidationResult) {
        self.switchedAccountID = switchedAccountID
        self.validationResult = validationResult
    }
}

public enum CLISwitchError: LocalizedError {
    case missingSourceFile
    case sourceFileMissing(URL)
    case validationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingSourceFile:
            return "The selected account does not have a backing auth file."
        case let .sourceFileMissing(url):
            return "The source auth file could not be found at \(url.path)."
        case let .validationFailed(message):
            return "Codex CLI validation failed after switching: \(message)"
        }
    }
}

public final class CLISwitchService {
    private let fileSystem: any FileSystem
    private let paths: CodexPaths
    private let validator: any CLIStatusValidating

    public init(
        fileSystem: any FileSystem = LocalFileSystem(),
        paths: CodexPaths = .live(),
        validator: any CLIStatusValidating = DefaultCLIStatusValidator()
    ) {
        self.fileSystem = fileSystem
        self.paths = paths
        self.validator = validator
    }

    @discardableResult
    public func switchToAccount(_ account: CodexAccount) throws -> CLISwitchResult {
        guard let sourceFile = account.sourceFile else {
            throw CLISwitchError.missingSourceFile
        }
        guard fileSystem.fileExists(at: sourceFile) else {
            throw CLISwitchError.sourceFileMissing(sourceFile)
        }

        let previousData = fileSystem.fileExists(at: paths.activeAuthFile) ? try fileSystem.read(from: paths.activeAuthFile) : nil
        let nextData = try fileSystem.read(from: sourceFile)
        try fileSystem.write(nextData, to: paths.activeAuthFile, options: .atomic)

        let validation = validator.validateCurrentLogin()
        switch validation {
        case .success:
            return CLISwitchResult(switchedAccountID: account.accountID, validationResult: validation)
        case let .failure(message):
            if let previousData {
                try fileSystem.write(previousData, to: paths.activeAuthFile, options: .atomic)
            }
            throw CLISwitchError.validationFailed(message)
        }
    }
}
