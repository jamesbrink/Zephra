import Foundation

/// The spelling a pairing payload is written in, which is not the one envelope bodies use.
///
/// Seconds since 1970 rather than ISO 8601, because a code is measured in grid modules and a
/// timestamp costs half as much as a number. Sorted keys for the same reason every other
/// encoder here has them: the same payload must produce the same code twice.
enum PairingJSON {
    /// The payload as the bytes a code carries.
    static func encode(_ payload: PairingPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(payload)
    }

    /// The payload those bytes are.
    static func decode(_ data: Data) throws -> PairingPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(PairingPayload.self, from: data)
    }
}
