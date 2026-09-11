import Foundation
import Synchronization

/// A pairing store that keeps its devices in memory and nowhere else.
///
/// For tests and for a preview host. Locked rather than actor-isolated because `PairingStore`'s
/// two calls are synchronous: the host reads the list while it is answering a handshake, and a
/// suspension there would be a second place a connection could be superseded.
public final class MemoryPairingStore: PairingStore, Sendable {
    private let devices: Mutex<[PairedDevice]>

    /// A store holding whatever it is given, which is usually nothing.
    public init(_ devices: [PairedDevice] = []) {
        self.devices = Mutex(devices)
    }

    public func load() throws -> [PairedDevice] { devices.withLock { $0 } }

    public func save(_ devices: [PairedDevice]) throws {
        self.devices.withLock { $0 = devices }
    }
}
