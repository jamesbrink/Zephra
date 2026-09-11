import Foundation
import ZephraLinkProtocol

/// One phone this Mac has agreed to talk to.
///
/// The keys are the pairing: a reconnection carries no secret, and what stands in for one is
/// the static key the two ends already share. Everything else here is for the person reading
/// the list — what the phone is called, when it was let in, and when it was last seen — so a
/// device nobody recognises can be picked out and revoked.
public struct PairedDevice: Codable, Hashable, Identifiable, Sendable {
    /// What the device published about itself at the handshake.
    public var keys: DevicePublicKeys
    /// What the phone calls itself, as it said in its `Hello`.
    public var name: String
    /// When the pairing was made.
    public var pairedAt: Date
    /// When it last opened a session, or nil for one that has not come back since.
    public var lastSeen: Date?

    /// The signing key, which is the one thing about a device that cannot change while the
    /// pairing lasts: a room is named after it and a relay join is signed with it.
    public var id: Data { keys.signing }

    /// Records one paired device.
    public init(keys: DevicePublicKeys, name: String, pairedAt: Date, lastSeen: Date? = nil) {
        self.keys = keys
        self.name = name
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
    }
}
