import Foundation

@testable import ZephraEngine

/// Hand-built PNG chunks for the text-chunk tests: the encoder's own builder is private and
/// only makes the two chunks Zephra writes, and these tests need the ones it must read past.
extension PNGTextChunksTests {
    /// One complete chunk: length, type, body, CRC. The encoder's own version is private and
    /// only builds the two chunks Zephra writes; these tests need the ones it has to read past.
    func chunk(type: String, body: Data) -> Data {
        var typed = Data(type.utf8)
        typed.append(body)
        return Data(
            Self.be32Bytes(UInt32(body.count)) + typed + Self.be32Bytes(PNGTextChunks.crc32(typed)))
    }

    /// A copy of `png` with `chunk` spliced in just ahead of the first `IDAT`, which is where
    /// text chunks belong.
    static func splicing(_ chunk: Data, into png: Data) throws -> Data {
        let bytes = Array(png)
        guard let image = try PNGTextChunks.spans(in: bytes).first(where: { $0.type == "IDAT" })
        else { throw PNGTextChunks.Failure.noImageData }
        var result = Data(bytes[..<image.start])
        result.append(chunk)
        result.append(contentsOf: bytes[image.start...])
        return result
    }

    static func be32Bytes(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) }
    }
}
