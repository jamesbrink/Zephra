import ZephraLinkProtocol

/// Where the phone keeps the two things it must not lose: who it is, and which Mac it knows.
///
/// A protocol rather than the keychain itself, because the keychain is the app's business and
/// this package is tested in milliseconds without one. The identity is a private key and
/// belongs behind the device's own protection; the paired host is public facts and rides along
/// so both are saved and cleared together.
public protocol LinkKeyStore: Sendable {
    /// This device's identity, or nil the first time it runs.
    func loadIdentity() throws -> DeviceIdentity?
    /// Keeps an identity, replacing whatever was there.
    func save(_ identity: DeviceIdentity) throws
    /// The Mac this device has paired with, or nil.
    func loadPairedHost() throws -> PairedHost?
    /// Keeps a pairing, or clears it with nil.
    func save(_ host: PairedHost?) throws
}
