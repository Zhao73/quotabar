import Foundation

public struct LocalStateQuotaProvider: QuotaProviding {
    public init() {}

    public func snapshot(for account: CodexAccount) async -> QuotaSnapshot {
        var warnings = ["No official quota source configured."]
        if account.lastRefreshAt == nil {
            warnings.append("The account has no known refresh timestamp.")
        }

        return QuotaSnapshot(
            status: .unavailable,
            refreshedAt: account.lastRefreshAt,
            sourceLabel: "Local Codex state",
            confidence: .high,
            warnings: warnings
        )
    }
}

