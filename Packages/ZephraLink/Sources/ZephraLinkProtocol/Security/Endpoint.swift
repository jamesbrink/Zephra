/// One address the phone may try, straight off the QR code.
public struct Endpoint: Codable, Hashable, Sendable {
    /// A host name or a literal address.
    public var host: String
    /// The port the Mac is listening on.
    public var port: UInt16

    /// Creates an address.
    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

extension Endpoint {
    private enum CodingKeys: String, CodingKey {
        case host = "h"
        case port = "p"
    }
}
