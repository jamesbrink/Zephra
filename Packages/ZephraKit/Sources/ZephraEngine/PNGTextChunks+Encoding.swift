import Foundation

/// Turning an entry into chunk bytes and back: the keyword rules, the Latin-1 or UTF-8 choice,
/// and the CRC-32 that closes every PNG chunk.
extension PNGTextChunks {
    /// One complete chunk for `entry`: length, type, body, CRC.
    ///
    /// Text that is representable in Latin-1 and free of NUL bytes goes in a `tEXt`, which is
    /// what Preview, the Finder's inspector, and exiftool read without ceremony. Anything else —
    /// a prompt with an em dash or an emoji in it — goes in an uncompressed `iTXt`, whose text
    /// is UTF-8 by definition.
    static func chunk(for entry: Entry) throws -> Data {
        let keyword = try validKeyword(entry.keyword)
        var body = Data(keyword)
        if let latin1 = latin1(entry.text), !latin1.contains(0) {
            body.append(0)
            body.append(contentsOf: latin1)
            return chunk(type: "tEXt", body: body)
        }
        // Keyword terminator, "not compressed", compression method 0, then an empty language
        // tag and an empty translated keyword, each terminated in turn.
        body.append(contentsOf: [0, 0, 0, 0, 0])
        body.append(contentsOf: Array(entry.text.utf8))
        return chunk(type: "iTXt", body: body)
    }

    /// The keyword and text of one text chunk, or nil for a chunk of another type, a malformed
    /// one, or compressed text this reader does not inflate.
    static func decode(_ span: Span, in bytes: [UInt8]) -> Entry? {
        let body = Array(bytes[span.body])
        guard let separator = body.firstIndex(of: 0),
              let keyword = latin1String(Array(body[..<separator]))
        else { return nil }
        switch span.type {
        case "tEXt":
            guard let text = latin1String(Array(body[(separator + 1)...])) else { return nil }
            return (keyword, text)
        case "iTXt":
            // Flag, method, then the language tag and the translated keyword to step over.
            guard body.count > separator + 3, body[separator + 1] == 0 else { return nil }
            var cursor = separator + 3
            for _ in 0..<2 {
                guard let end = body[cursor...].firstIndex(of: 0) else { return nil }
                cursor = end + 1
            }
            return (keyword, String(decoding: body[cursor...], as: UTF8.self))
        default:
            return nil
        }
    }

    /// The CRC-32 a PNG chunk ends with, taken over the type bytes followed by the body.
    static func crc32(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func chunk(type: String, body: Data) -> Data {
        var typed = Data(type.utf8)
        typed.append(body)
        var out = Data(be32Bytes(UInt32(body.count)))
        out.append(typed)
        out.append(contentsOf: be32Bytes(crc32(typed)))
        return out
    }

    /// PNG keywords are 1 to 79 printable characters with no space at either end. Zephra's own
    /// keywords are ASCII, so this is stricter than the format allows and simpler for it.
    private static func validKeyword(_ keyword: String) throws -> [UInt8] {
        let bytes = Array(keyword.utf8)
        guard (1...79).contains(bytes.count),
              bytes.allSatisfy({ (32...126).contains($0) }),
              bytes.first != 32, bytes.last != 32
        else { throw Failure.invalidKeyword(keyword) }
        return bytes
    }

    private static func latin1(_ text: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            guard scalar.value <= 255 else { return nil }
            bytes.append(UInt8(scalar.value))
        }
        return bytes
    }

    private static func latin1String(_ bytes: [UInt8]) -> String? {
        String(bytes: bytes, encoding: .isoLatin1)
    }

    private static func be32Bytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ]
    }

    /// The standard CRC-32 table, built once from the PNG specification's polynomial.
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }
}
