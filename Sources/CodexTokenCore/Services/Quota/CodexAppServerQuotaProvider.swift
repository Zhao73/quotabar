import Foundation

public protocol CodexAppServerRateLimitReading: Sendable {
    func readRateLimits(codexHomeDirectory: URL?) async throws -> CodexAppServerRateLimitsResponse
}

public enum CodexAppServerRateLimitError: LocalizedError {
    case launchFailed(String)
    case invalidResponse
    case timedOut

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            return message
        case .invalidResponse:
            return "Codex app-server returned an invalid rate limit payload."
        case .timedOut:
            return "Timed out while reading rate limits from codex app-server."
        }
    }
}

public struct CodexAppServerRateLimitsResponse: Decodable, Equatable, Sendable {
    public let rateLimits: RateLimitSnapshot
    public let rateLimitsByLimitId: [String: RateLimitSnapshot]?

    public struct RateLimitSnapshot: Decodable, Equatable, Sendable {
        public let credits: CreditsSnapshot?
        public let limitId: String?
        public let limitName: String?
        public let planType: String?
        public let primary: RateLimitWindow?
        public let secondary: RateLimitWindow?
    }

    public struct CreditsSnapshot: Decodable, Equatable, Sendable {
        public let balance: String?
        public let hasCredits: Bool
        public let unlimited: Bool
    }

    public struct RateLimitWindow: Decodable, Equatable, Sendable {
        public let resetsAt: Int64?
        public let usedPercent: Int
        public let windowDurationMins: Int?
    }
}

public final class DefaultCodexAppServerRateLimitReader: CodexAppServerRateLimitReading {
    public init() {}

    public func readRateLimits(codexHomeDirectory: URL? = nil) async throws -> CodexAppServerRateLimitsResponse {
        try await withCheckedThrowingContinuation { continuation in
            let runtime = ReaderRuntime()

            let finish: @Sendable (Result<CodexAppServerRateLimitsResponse, Error>) -> Void = { result in
                let shouldFinish = runtime.withLock { () -> Bool in
                    guard !runtime.hasFinished else { return false }
                    runtime.hasFinished = true
                    return true
                }

                guard shouldFinish else { return }

                runtime.outputPipe.fileHandleForReading.readabilityHandler = nil
                runtime.errorPipe.fileHandleForReading.readabilityHandler = nil

                if runtime.process.isRunning {
                    runtime.process.terminate()
                }

                continuation.resume(with: result)
            }

            runtime.outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                let chunk = String(decoding: data, as: UTF8.self)
                let lines = runtime.withLock { () -> [String] in
                    runtime.stdoutBuffer += chunk
                    let lines = runtime.stdoutBuffer.components(separatedBy: "\n")
                    runtime.stdoutBuffer = lines.last ?? ""
                    return Array(lines.dropLast())
                }

                for line in lines {
                    guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    if let response = try? JSONDecoder().decode(JSONRPCRateLimitEnvelope.self, from: Data(line.utf8)) {
                        finish(.success(response.result))
                        return
                    }
                }
            }

            runtime.errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = String(decoding: data, as: UTF8.self)
                runtime.withLock {
                    runtime.stderrBuffer += chunk
                }
            }

            runtime.process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            runtime.process.arguments = ["-lc", "codex app-server --listen stdio://"]
            runtime.process.standardInput = runtime.inputPipe
            runtime.process.standardOutput = runtime.outputPipe
            runtime.process.standardError = runtime.errorPipe
            if let codexHomeDirectory {
                var environment = ProcessInfo.processInfo.environment
                let path = codexHomeDirectory.path.hasSuffix("/") ? codexHomeDirectory.path : codexHomeDirectory.path + "/"
                environment["CODEX_HOME"] = path
                runtime.process.environment = environment
            }

            do {
                try runtime.process.run()
            } catch {
                finish(.failure(CodexAppServerRateLimitError.launchFailed(error.localizedDescription)))
                return
            }

            let initialize = JSONRPCRequestEnvelope(
                id: 1,
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "CodexToken",
                        "version": "0.1"
                    ],
                    "capabilities": [
                        "experimentalApi": true
                    ]
                ]
            )

            let read = JSONRPCRequestEnvelope(
                id: 2,
                method: "account/rateLimits/read",
                params: NSNull()
            )

            let encoder = JSONEncoder()
            guard let initializeData = try? encoder.encode(initialize),
                  let readData = try? encoder.encode(read)
            else {
                finish(.failure(CodexAppServerRateLimitError.invalidResponse))
                return
            }

            runtime.inputPipe.fileHandleForWriting.write(initializeData)
            runtime.inputPipe.fileHandleForWriting.write(Data("\n".utf8))
            runtime.inputPipe.fileHandleForWriting.write(readData)
            runtime.inputPipe.fileHandleForWriting.write(Data("\n".utf8))

            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                let (alreadyFinished, currentError) = runtime.withLock {
                    (runtime.hasFinished, runtime.stderrBuffer)
                }
                guard !alreadyFinished else { return }

                if !currentError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finish(.failure(CodexAppServerRateLimitError.launchFailed(currentError.trimmingCharacters(in: .whitespacesAndNewlines))))
                } else {
                    finish(.failure(CodexAppServerRateLimitError.timedOut))
                }
            }
        }
    }
}

private final class ReaderRuntime: @unchecked Sendable {
    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let lock = NSLock()

    var stdoutBuffer = ""
    var stderrBuffer = ""
    var hasFinished = false

    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

public struct CodexAppServerQuotaProvider: QuotaProviding {
    private let reader: any CodexAppServerRateLimitReading
    private let codexHomeDirectory: URL?

    public init(
        codexHomeDirectory: URL? = nil,
        reader: any CodexAppServerRateLimitReading = DefaultCodexAppServerRateLimitReader()
    ) {
        self.codexHomeDirectory = codexHomeDirectory
        self.reader = reader
    }

    public func snapshot(for account: CodexAccount) async -> QuotaSnapshot {
        do {
            let response = try await reader.readRateLimits(codexHomeDirectory: codexHomeDirectory)
            let rateLimits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
            let refreshedAt = Date()

            var warnings: [String] = []
            if let planType = rateLimits.planType {
                warnings.append("Plan: \(planType)")
            }
            if let credits = rateLimits.credits, !credits.unlimited {
                warnings.append("Credits balance: \(credits.balance ?? "0")")
            }

            return QuotaSnapshot(
                status: .experimental,
                refreshedAt: refreshedAt,
                sourceLabel: "Codex app-server",
                confidence: .high,
                warnings: warnings,
                primaryWindow: makeWindow(rateLimits.primary),
                secondaryWindow: makeWindow(rateLimits.secondary)
            )
        } catch {
            return QuotaSnapshot(
                status: .error,
                refreshedAt: account.lastRefreshAt,
                sourceLabel: "Codex app-server",
                confidence: .medium,
                warnings: ["Failed to read Codex rate limits from app-server."],
                errorDescription: error.localizedDescription
            )
        }
    }

    private func makeWindow(_ window: CodexAppServerRateLimitsResponse.RateLimitWindow?) -> QuotaWindowSnapshot? {
        guard let window else { return nil }
        return QuotaWindowSnapshot(
            usedPercent: window.usedPercent,
            windowDurationMinutes: window.windowDurationMins,
            resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private struct JSONRPCRequestEnvelope: Encodable {
    let id: Int
    let method: String
    let params: AnyEncodable

    init(id: Int, method: String, params: Any) {
        self.id = id
        self.method = method
        self.params = AnyEncodable(params)
    }
}

private struct JSONRPCRateLimitEnvelope: Decodable {
    let id: Int
    let result: CodexAppServerRateLimitsResponse
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ value: Any) {
        self.encodeClosure = { encoder in
            var container = encoder.singleValueContainer()
            switch value {
            case let string as String:
                try container.encode(string)
            case let int as Int:
                try container.encode(int)
            case let bool as Bool:
                try container.encode(bool)
            case let dict as [String: Any]:
                try container.encode(dict.mapValues { AnyEncodable($0) })
            case let null as NSNull:
                _ = null
                try container.encodeNil()
            default:
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON-RPC payload.")
                )
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
