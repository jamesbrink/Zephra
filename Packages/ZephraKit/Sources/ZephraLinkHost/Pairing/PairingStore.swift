import Foundation

/// Where the paired devices are kept between launches.
///
/// A protocol rather than a concrete keychain, for the reason every other side door into the
/// engine is one: the app hands in a keychain-backed store, and a test hands in
/// `MemoryPairingStore`, so the whole of pairing is exercised in milliseconds without asking
/// the system for an item it would have to clean up afterwards.
///
/// Throwing on both sides on purpose. A keychain that will not answer is not an empty list:
/// treating a locked keychain as "no devices are paired" would quietly unpair every phone.
public protocol PairingStore: Sendable {
    /// Every device paired with this Mac, in no particular order.
    func load() throws -> [PairedDevice]
    /// Replaces the list wholesale.
    func save(_ devices: [PairedDevice]) throws
}
