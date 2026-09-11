import Foundation
import ZephraLinkProtocol

/// A store that forgets everything when the process ends, for tests and for a frozen preview.
///
/// It keeps the identity's raw bytes rather than the value, so what a test exercises is the
/// same round trip the keychain does: saved as sixty-four bytes, read back as the same device.
public final class MemoryLinkKeyStore: LinkKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var identityBytes: Data?
    private var host: PairedHost?

    /// An empty store, or one that already knows a device and a Mac.
    public init(identity: DeviceIdentity? = nil, pairedHost: PairedHost? = nil) {
        identityBytes = identity?.rawRepresentation
        host = pairedHost
    }

    public func loadIdentity() throws -> DeviceIdentity? {
        guard let bytes = lock.withLock({ identityBytes }) else { return nil }
        return try DeviceIdentity(rawRepresentation: bytes)
    }

    public func save(_ identity: DeviceIdentity) throws {
        lock.withLock { identityBytes = identity.rawRepresentation }
    }

    public func loadPairedHost() throws -> PairedHost? { lock.withLock { host } }

    public func save(_ host: PairedHost?) throws { lock.withLock { self.host = host } }
}
