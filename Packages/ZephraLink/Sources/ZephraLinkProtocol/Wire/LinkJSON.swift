import Foundation

/// The one JSON spelling every envelope body uses.
///
/// Sorted keys and ISO 8601 dates, so the same value encodes to the same bytes on both ends.
/// That is not tidiness: the handshake hashes a `Hello` the responder decoded and re-encoded,
/// and a golden-string test is only a test while the spelling is fixed.
public enum LinkJSON {
    /// The encoder every body is written with.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// The decoder every body is read with.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// One value as the bytes an envelope carries.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    /// One value read back out of those bytes.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }
}
