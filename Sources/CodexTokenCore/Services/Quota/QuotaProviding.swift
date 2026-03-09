import Foundation

public protocol QuotaProviding: Sendable {
    func snapshot(for account: CodexAccount) async -> QuotaSnapshot
}

public struct CompositeQuotaProvider: QuotaProviding {
    public let primary: any QuotaProviding
    public let fallback: any QuotaProviding

    public init(primary: any QuotaProviding, fallback: any QuotaProviding) {
        self.primary = primary
        self.fallback = fallback
    }

    public func snapshot(for account: CodexAccount) async -> QuotaSnapshot {
        let primarySnapshot = await primary.snapshot(for: account)
        switch primarySnapshot.status {
        case .available, .experimental:
            return primarySnapshot
        case .unavailable, .error:
            return await fallback.snapshot(for: account)
        }
    }
}
