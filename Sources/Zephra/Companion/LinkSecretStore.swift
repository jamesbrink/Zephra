import Foundation
import ZephraLinkHost
import ZephraLinkProtocol
import os

/// Where a minting that costs somebody their pairings is said out loud.
///
/// A file-scope constant because the rule below is a protocol extension and a protocol extension
/// may hold no stored property of its own; one logger for the one sentence is cheaper than a
/// logger on each of the three stores that conform.
private nonisolated let mintingLogger = Logger(subsystem: "io.zephra", category: "companion")

/// What keeps this Mac's link secrets between launches: its own identity, and the phones it has
/// agreed to talk to.
///
/// One surface with two implementations — `LinkKeychainStore` and `LinkFileStore` — because
/// which one a launch gets is decided by this build's signature rather than by anything about
/// the link, and `LinkKeychain` is the facade that picks. The identity is raw bytes here rather
/// than a `DeviceIdentity` so that the one rule about a missing identity lives in one place,
/// below, instead of once per store.
///
/// Throwing on every side, like `PairingStore`: a store that will not answer is not an empty
/// list, and treating a locked keychain as "no devices are paired" would quietly unpair every
/// phone.
nonisolated protocol LinkSecretStore: PairingStore {
    /// This Mac's identity as it was stored, or nil where there is none yet.
    func identityBytes() throws -> Data?
    /// Keeps this Mac's identity, the first time one is made.
    func writeIdentity(_ bytes: Data) throws
    /// Forgets the identity and every pairing, for a reset that should look like a Mac that has
    /// never linked.
    func removeAll() throws
}

extension LinkSecretStore {
    /// This Mac's identity, made and stored the first time it is asked for.
    ///
    /// A new identity would look like a new device and every pairing would be gone, so the one
    /// already stored always wins. Bytes that are there but are not an identity — something a
    /// build that stored another shape left behind — are replaced rather than thrown, since the
    /// alternative is an app that cannot start its link at all.
    nonisolated func identity() throws -> DeviceIdentity {
        try identity { note in mintingLogger.error("\(note, privacy: .public)") }
    }

    /// The same, saying out loud what a minting costs when it costs anything.
    ///
    /// A Mac with no identity and phones still paired to it is not a first launch: it is a Mac
    /// whose identity went missing — the migration that deleted the item it had just read is how
    /// that happened once — and the new key it is about to mint puts it in a room none of those
    /// phones will ever find. There is no way back from here, so it mints; what it must not do is
    /// mint in silence, since from the outside the only symptom is a phone that never connects
    /// again. `report` is injected so a test reads the sentence rather than the log.
    nonisolated func identity(reporting report: (String) -> Void) throws -> DeviceIdentity {
        if let bytes = try identityBytes(), let identity = try? DeviceIdentity(rawRepresentation: bytes) {
            return identity
        }
        let paired = ((try? load()) ?? []).count
        if paired > 0 {
            report(
                "companion secrets: no identity was stored, so a new one is being made while "
                    + "\(paired) paired device(s) are still on file. Those devices are paired with "
                    + "the identity that has gone and have to be paired again.")
        }
        let identity = DeviceIdentity()
        try writeIdentity(identity.rawRepresentation)
        return identity
    }
}
