import Foundation
import ZephraLinkProtocol

/// The Mac this phone has paired with, as it is kept between launches.
///
/// The keys are what a reconnection stands on: after the first handshake the pairing secret is
/// gone and the two static keys are what the two ends share, so losing this is losing the
/// pairing. The endpoints are the addresses off the QR code, tried first because they are
/// usually right; the room is the fallback, and it is derived from the signing key, so it stays
/// true however the network moves.
public struct PairedHost: Codable, Hashable, Sendable {
    /// What the Mac is called.
    public var name: String
    /// Its published keys.
    public var keys: DevicePublicKeys
    /// Addresses to try on the local network, best first.
    public var endpoints: [Endpoint]
    /// The relay room to fall back to.
    public var roomID: RoomID
    /// When the pairing was made.
    public var pairedAt: Date

    /// Creates a record of one pairing.
    public init(
        name: String, keys: DevicePublicKeys, endpoints: [Endpoint], roomID: RoomID, pairedAt: Date
    ) {
        self.name = name
        self.keys = keys
        self.endpoints = endpoints
        self.roomID = roomID
        self.pairedAt = pairedAt
    }

    /// The Mac a pairing code names, paired now.
    public init(_ payload: PairingPayload, at date: Date = Date()) {
        self.init(
            name: payload.hostName, keys: payload.keys, endpoints: payload.endpoints,
            roomID: payload.roomID, pairedAt: date)
    }
}
