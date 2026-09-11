import Foundation

/// The link a QR code is, and reading one back.
///
/// A custom scheme rather than a web address: nothing about pairing should reach a server, and
/// a `zephra://` link opens the app that knows what to do with it or nothing at all. The
/// payload is one query item so the code is one string, whatever a scanner hands back.
public enum PairingURL {
    /// The scheme the link uses.
    public static let scheme = "zephra"
    /// The host the link uses.
    public static let host = "pair"

    /// The link for one payload.
    public static func encode(_ payload: PairingPayload) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "v", value: String(payload.version)),
            URLQueryItem(name: "d", value: Base64URL.encode(try PairingJSON.encode(payload))),
        ]
        guard let url = components.url else {
            throw LinkError(code: .badRequest, reason: "That pairing code could not be written.")
        }
        return url
    }

    /// The payload a scanned string holds.
    ///
    /// The whole link or the bare payload, because a scanner may hand back either and a person
    /// pasting a code by hand will paste whichever half they were shown. Whitespace is trimmed
    /// for the same reason.
    public static func decode(_ text: String) throws -> PairingPayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = try payloadText(in: trimmed)
        guard let data = Base64URL.decode(encoded) else {
            throw LinkError(code: .badRequest, reason: "That is not a Zephra pairing code.")
        }
        return try PairingJSON.decode(data)
    }

    private static func payloadText(in trimmed: String) throws -> String {
        guard trimmed.contains("://") else { return trimmed }
        guard let components = URLComponents(string: trimmed),
              components.scheme == scheme, components.host == host,
              let value = components.queryItems?.first(where: { $0.name == "d" })?.value
        else {
            throw LinkError(code: .badRequest, reason: "That is not a Zephra pairing code.")
        }
        return value
    }
}
