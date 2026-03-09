import Foundation

public struct AccountMetadata: Codable, Equatable, Sendable {
    public var customName: String?
    public var remark: String?
    public var sortOrder: Int
    public var isHidden: Bool

    public init(
        customName: String? = nil,
        remark: String? = nil,
        sortOrder: Int = 0,
        isHidden: Bool = false
    ) {
        self.customName = customName
        self.remark = remark
        self.sortOrder = sortOrder
        self.isHidden = isHidden
    }
}

