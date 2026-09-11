import Foundation

/// Everything a QR code carries: who the Mac is, where to reach it, and the secret that makes
/// this the connection the person meant.
///
/// The coding keys are one letter each and the date is a count of seconds. Not shorthand for
/// its own sake: the payload has to fit a code somebody photographs across a desk, and every
/// byte is another module in the grid. The long names are in this file, where they are read.
public struct PairingPayload: Codable, Hashable, Sendable {
    /// The most addresses a code carries. Four is every interface a Mac plausibly has; a fifth
    /// costs grid density for an address the phone would try last anyway.
    public static let endpointLimit = 4

    /// Which protocol the Mac speaks.
    public var version: Int
    /// What the Mac is called.
    public var hostName: String
    /// The Mac's published keys.
    public var keys: DevicePublicKeys
    /// Addresses to try, best first; at most `endpointLimit`.
    public var endpoints: [Endpoint]
    /// The relay room to fall back to, which is the hash of the signing key.
    public var roomID: RoomID
    /// The pairing secret, sixteen bytes.
    public var secret: Data
    /// When the secret stops being accepted.
    public var expiresAt: Date

    /// Creates a payload, keeping at most `endpointLimit` addresses.
    public init(
        version: Int = LinkProtocolVersion.current,
        hostName: String,
        keys: DevicePublicKeys,
        endpoints: [Endpoint],
        secret: Data,
        expiresAt: Date
    ) {
        self.version = version
        self.hostName = hostName
        self.keys = keys
        self.endpoints = Array(endpoints.prefix(Self.endpointLimit))
        self.roomID = keys.roomID
        self.secret = secret
        self.expiresAt = expiresAt
    }

    /// The payload for one live pairing secret.
    public init(hostName: String, keys: DevicePublicKeys, endpoints: [Endpoint], secret: PairingSecret) {
        self.init(
            hostName: hostName, keys: keys, endpoints: endpoints, secret: secret.bytes,
            expiresAt: secret.expiresAt)
    }

    /// Whether the code is past its time.
    public func isExpired(at date: Date = Date()) -> Bool { date >= expiresAt }

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case hostName = "n"
        case keys = "k"
        case endpoints = "e"
        case roomID = "r"
        case secret = "s"
        case expiresAt = "x"
    }
}
