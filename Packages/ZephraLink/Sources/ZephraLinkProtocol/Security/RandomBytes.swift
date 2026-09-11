import CryptoKit
import Foundation

/// Random bytes from the system's own generator.
///
/// Through `SymmetricKey` rather than a loop over `UInt8.random`, so there is one place in the
/// package that says where randomness comes from and it is the one CryptoKit uses for keys.
enum RandomBytes {
    /// `count` bytes, unpredictable.
    static func make(_ count: Int) -> Data {
        SymmetricKey(size: .init(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }
}
