import Foundation

public protocol ClaudeOAuthUsageFetching: Sendable {
    func fetchUsage(accessToken: String) async throws -> ClaudeOAuthUsageResponse
}

public struct ClaudeOAuthQuotaProvider: QuotaProviding {
    private let credentialStore: ClaudeOAuthCredentialStore
    private let usageFetcher: any ClaudeOAuthUsageFetching

    public init(
        credentialStore: ClaudeOAuthCredentialStore = ClaudeOAuthCredentialStore(),
        usageFetcher: any ClaudeOAuthUsageFetching = ClaudeOAuthUsageClient()
    ) {
        self.credentialStore = credentialStore
        self.usageFetcher = usageFetcher
    }

    public func snapshot(for account: CodexAccount) async -> QuotaSnapshot {
        do {
            let credentials = try credentialStore.load()

            if credentials.isExpired {
                return QuotaSnapshot(
                    status: .error,
                    refreshedAt: Date(),
                    sourceLabel: "Claude OAuth",
                    confidence: .high,
                    warnings: ["token_expired"],
                    errorDescription: "Claude OAuth token has expired. Please re-login."
                )
            }

            if credentials.isExpiringSoon {
                let usage = try await usageFetcher.fetchUsage(accessToken: credentials.accessToken)
                let snapshot = Self.makeSnapshot(from: usage, plan: credentials.rateLimitTier)
                var warnings = snapshot.warnings
                warnings.append("token_expiring_soon")
                if let minutes = credentials.expiresInMinutes {
                    warnings.append("expires_in_minutes:\(minutes)")
                }
                return QuotaSnapshot(
                    status: snapshot.status,
                    value: snapshot.value,
                    unit: snapshot.unit,
                    refreshedAt: snapshot.refreshedAt,
                    sourceLabel: snapshot.sourceLabel,
                    confidence: snapshot.confidence,
                    warnings: warnings,
                    primaryWindow: snapshot.primaryWindow,
                    secondaryWindow: snapshot.secondaryWindow
                )
            }

            let usage = try await usageFetcher.fetchUsage(accessToken: credentials.accessToken)
            return Self.makeSnapshot(from: usage, plan: credentials.rateLimitTier)
        } catch {
            let isAuthError = (error as NSError).code == 1 && (error as NSError).domain == "claude"
            if isAuthError {
                return QuotaSnapshot(
                    status: .error,
                    refreshedAt: Date(),
                    sourceLabel: "Claude OAuth",
                    confidence: .high,
                    warnings: ["token_expired"],
                    errorDescription: "Claude OAuth authentication failed. Please re-login."
                )
            }
            return QuotaSnapshot(
                status: .unavailable,
                refreshedAt: account.lastRefreshAt,
                sourceLabel: "Claude OAuth",
                confidence: .medium,
                warnings: ["Claude OAuth data unavailable."],
                errorDescription: error.localizedDescription
            )
        }
    }

    private static func makeSnapshot(from usage: ClaudeOAuthUsageResponse, plan: String?) -> QuotaSnapshot {
        var warnings: [String] = []
        if let plan = plan, !plan.isEmpty {
            warnings.append("Plan: \(plan)")
        }

        return QuotaSnapshot(
            status: .experimental,
            refreshedAt: Date(),
            sourceLabel: "Claude OAuth",
            confidence: .high,
            warnings: warnings,
            primaryWindow: makeWindow(usage.fiveHour, duration: 300),
            secondaryWindow: makeWindow(usage.sevenDay, duration: 10_080)
        )
    }

    private static func makeWindow(_ window: ClaudeOAuthUsageWindow?, duration: Int) -> QuotaWindowSnapshot? {
        guard let window else { return nil }
        let usedPercent = Int((window.utilization ?? 0) * 100)
        let resetsAt = parseDate(window.resetsAt)
        return QuotaWindowSnapshot(
            usedPercent: max(0, min(100, usedPercent)),
            windowDurationMinutes: duration,
            resetsAt: resetsAt
        )
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }
}

public struct ClaudeOAuthUsageResponse: Decodable, Sendable {
    public let fiveHour: ClaudeOAuthUsageWindow?
    public let sevenDay: ClaudeOAuthUsageWindow?
    public let sevenDayOpus: ClaudeOAuthUsageWindow?
    public let sevenDaySonnet: ClaudeOAuthUsageWindow?
    public let iguanaNecktie: ClaudeOAuthUsageWindow?
    public let extraUsage: ClaudeOAuthExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case iguanaNecktie = "iguana_necktie"
        case extraUsage = "extra_usage"
    }
}

public struct ClaudeOAuthUsageWindow: Decodable, Sendable {
    public let utilization: Double?
    public let resetsAt: String?
}

public struct ClaudeOAuthExtraUsage: Decodable, Sendable {
    public let isEnabled: Bool?
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let utilization: Double?
    public let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
    }
}

public struct ClaudeOAuthUsageClient: ClaudeOAuthUsageFetching {
    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func fetchUsage(accessToken: String) async throws -> ClaudeOAuthUsageResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "claude", code: 1, userInfo: nil)
        }

        return try JSONDecoder().decode(ClaudeOAuthUsageResponse.self, from: data)
    }
}

extension ClaudeOAuthUsageClient: @unchecked Sendable {}

extension ClaudeOAuthQuotaProvider {
    public struct StaticFetcher: ClaudeOAuthUsageFetching, Sendable {
        private let response: ClaudeOAuthUsageResponse?
        private let errorDescription: String?

        public init(response: ClaudeOAuthUsageResponse) {
            self.response = response
            self.errorDescription = nil
        }

        public init(response: ClaudeOAuthUsageResponse?) {
            self.response = response
            self.errorDescription = nil
        }

        public init(error: Error) {
            self.response = nil
            self.errorDescription = error.localizedDescription
        }

        public func fetchUsage(accessToken: String) async throws -> ClaudeOAuthUsageResponse {
            if let errorDescription {
                throw NSError(
                    domain: "claude.oauth",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: errorDescription]
                )
            }
            guard let response else {
                throw NSError(
                    domain: "claude.oauth",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing Claude OAuth usage response"]
                )
            }
            return response
        }
    }
}
