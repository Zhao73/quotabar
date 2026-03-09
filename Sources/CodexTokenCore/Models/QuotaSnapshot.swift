import Foundation

public struct QuotaWindowSnapshot: Codable, Equatable, Sendable {
    public let usedPercent: Int
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?

    public init(
        usedPercent: Int,
        windowDurationMinutes: Int? = nil,
        resetsAt: Date? = nil
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }
}

public enum QuotaStatus: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case experimental
    case error
}

public enum QuotaConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let status: QuotaStatus
    public let value: Double?
    public let unit: String?
    public let refreshedAt: Date?
    public let sourceLabel: String
    public let confidence: QuotaConfidence
    public let warnings: [String]
    public let errorDescription: String?
    public let primaryWindow: QuotaWindowSnapshot?
    public let secondaryWindow: QuotaWindowSnapshot?

    public init(
        status: QuotaStatus,
        value: Double? = nil,
        unit: String? = nil,
        refreshedAt: Date? = nil,
        sourceLabel: String,
        confidence: QuotaConfidence,
        warnings: [String] = [],
        errorDescription: String? = nil,
        primaryWindow: QuotaWindowSnapshot? = nil,
        secondaryWindow: QuotaWindowSnapshot? = nil
    ) {
        self.status = status
        self.value = value
        self.unit = unit
        self.refreshedAt = refreshedAt
        self.sourceLabel = sourceLabel
        self.confidence = confidence
        self.warnings = warnings
        self.errorDescription = errorDescription
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }
}
