import CryptoKit
import Foundation
import ZephraCore

/// Reference identity for offers and receipts, without pixels or session-local blob IDs.
public struct GenerationInput: Codable, Hashable, Sendable {
    public let byteCount: Int
    public let digest: String
    public let originHost: HostID?
    public let dimensions: ImageSize?
    public init(data: Data, originHost: HostID? = nil, dimensions: ImageSize? = nil) {
        byteCount = data.count
        digest = Self.digest(data)
        self.originHost = originHost
        self.dimensions = dimensions
    }
    public func matches(_ data: Data) -> Bool {
        byteCount == data.count && digest == Self.digest(data)
    }
    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
