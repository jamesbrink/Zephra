import CryptoKit
import Foundation

/// Stable ownership independent of host name, endpoint and relay connection.
public struct HostID: Codable, Hashable, Sendable, Identifiable, Comparable {
    public let rawValue: String
    public var id: String { rawValue }
    public init(keys: DevicePublicKeys) {
        rawValue = SHA256.hash(data: keys.signing).map { String(format: "%02x", $0) }.joined()
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
