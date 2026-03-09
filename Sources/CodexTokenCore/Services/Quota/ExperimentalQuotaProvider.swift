import Foundation

public struct ExperimentalQuotaConfiguration: Equatable, Sendable {
    public var shellCommand: String?

    public init(shellCommand: String? = nil) {
        self.shellCommand = shellCommand
    }

    public static let disabled = ExperimentalQuotaConfiguration(shellCommand: nil)
}

public protocol ShellCommandRunning: Sendable {
    func run(shellCommand: String) throws -> ShellCommandResult
}

public struct ShellCommandResult: Sendable {
    public let standardOutput: String
    public let standardError: String
    public let exitCode: Int32

    public init(standardOutput: String, standardError: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}

public struct DefaultShellCommandRunner: ShellCommandRunning {
    public init() {}

    public func run(shellCommand: String) throws -> ShellCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", shellCommand]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return ShellCommandResult(standardOutput: output, standardError: error, exitCode: process.terminationStatus)
    }
}

public struct ExperimentalQuotaProvider: QuotaProviding {
    private let configuration: ExperimentalQuotaConfiguration
    private let commandRunner: any ShellCommandRunning

    public init(
        configuration: ExperimentalQuotaConfiguration,
        commandRunner: any ShellCommandRunning = DefaultShellCommandRunner()
    ) {
        self.configuration = configuration
        self.commandRunner = commandRunner
    }

    public func snapshot(for account: CodexAccount) async -> QuotaSnapshot {
        guard let shellCommand = configuration.shellCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
              !shellCommand.isEmpty
        else {
            return QuotaSnapshot(
                status: .unavailable,
                refreshedAt: account.lastRefreshAt,
                sourceLabel: "Experimental quota provider",
                confidence: .low,
                warnings: ["Experimental quota provider is disabled."]
            )
        }

        do {
            let result = try commandRunner.run(shellCommand: shellCommand)
            guard result.exitCode == 0 else {
                return QuotaSnapshot(
                    status: .error,
                    refreshedAt: account.lastRefreshAt,
                    sourceLabel: "Experimental quota provider",
                    confidence: .low,
                    warnings: ["The external quota command failed."],
                    errorDescription: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(ExternalQuotaPayload.self, from: Data(result.standardOutput.utf8))
            return QuotaSnapshot(
                status: payload.status,
                value: payload.value,
                unit: payload.unit,
                refreshedAt: payload.refreshedAt ?? account.lastRefreshAt,
                sourceLabel: payload.sourceLabel,
                confidence: payload.confidence,
                warnings: payload.warnings
            )
        } catch {
            return QuotaSnapshot(
                status: .error,
                refreshedAt: account.lastRefreshAt,
                sourceLabel: "Experimental quota provider",
                confidence: .low,
                warnings: ["The experimental quota output could not be parsed."],
                errorDescription: error.localizedDescription
            )
        }
    }
}

private struct ExternalQuotaPayload: Decodable {
    let status: QuotaStatus
    let value: Double?
    let unit: String?
    let refreshedAt: Date?
    let sourceLabel: String
    let confidence: QuotaConfidence
    let warnings: [String]
}
