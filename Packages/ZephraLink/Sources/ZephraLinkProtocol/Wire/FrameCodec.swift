import Foundation

/// The bytes a frame is: one kind byte, then the body.
///
/// The kind is outside the body on purpose. It is what the secure channel authenticates as
/// additional data, so a frame cannot be replayed as the other kind, and it is what lets the
/// receiver choose a parser without first decoding anything.
public enum FrameCodec {
    /// The leading byte of an envelope frame.
    public static let envelopeKind: UInt8 = 0x01
    /// The leading byte of a chunk frame.
    public static let chunkKind: UInt8 = 0x02
    /// A chunk's header: 16 bytes of blob id, then two big-endian `UInt32`.
    static let chunkHeaderSize = 16 + 4 + 4

    /// One frame as bytes.
    public static func encode(_ frame: Frame) throws -> Data {
        var data = Data([frame.kind])
        data.append(try body(of: frame))
        return data
    }

    /// The frame those bytes are.
    public static func decode(_ data: Data) throws -> Frame {
        guard let kind = data.first else {
            throw LinkError(code: .badRequest, reason: "An empty frame arrived.")
        }
        return try frame(kind: kind, body: Data(data.dropFirst()))
    }

    /// A frame's body alone, which is what the channel encrypts.
    public static func body(of frame: Frame) throws -> Data {
        switch frame {
        case .envelope(let envelope): try LinkJSON.encode(envelope)
        case .chunk(let chunk): encode(chunk)
        }
    }

    /// The frame a kind byte and a body make.
    public static func frame(kind: UInt8, body: Data) throws -> Frame {
        switch kind {
        case envelopeKind: .envelope(try LinkJSON.decode(Envelope.self, from: body))
        case chunkKind: .chunk(try decodeChunk(body))
        default:
            throw LinkError(code: .unsupported, reason: "A frame of an unknown kind arrived.")
        }
    }
}
