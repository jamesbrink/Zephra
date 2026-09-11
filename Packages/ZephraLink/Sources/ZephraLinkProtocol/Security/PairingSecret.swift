import CryptoKit
import Foundation

/// The short-lived secret a QR code carries, which is what makes a first connection the one the
/// person meant.
///
/// Sixteen random bytes, live for two minutes. It is mixed into the handshake as the key
/// schedule's salt, so a device that did not read the code derives different keys and fails at
/// the first tag rather than at some later check. Short-lived because a code photographed off a
/// screen is a secret for as long as the screen remembers it.
public struct PairingSecret: Hashable, Sendable {
    /// How long a code is good for.
    public static let lifetime: TimeInterval = 120
    /// How many bytes the secret is.
    public static let byteCount = 16

    /// The bytes themselves.
    public let bytes: Data
    /// When they stop being accepted.
    public let expiresAt: Date

    /// A fresh secret, live from now.
    public init(now: Date = Date()) {
        bytes = RandomBytes.make(Self.byteCount)
        expiresAt = now.addingTimeInterval(Self.lifetime)
    }

    /// A secret read back from a code.
    public init(bytes: Data, expiresAt: Date) {
        self.bytes = bytes
        self.expiresAt = expiresAt
    }

    /// Whether it is past its time.
    public func isExpired(at date: Date = Date()) -> Bool { date >= expiresAt }
}
