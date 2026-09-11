/// Everything that crosses the channel, which is exactly two things.
///
/// An envelope is a message with a JSON body; a chunk is a slice of a blob with a binary
/// header. One enum rather than two codecs, because the channel seals and opens frames and has
/// to know nothing else about them.
public enum Frame: Hashable, Sendable {
    /// A message.
    case envelope(Envelope)
    /// A piece of a blob.
    case chunk(BlobChunk)

    /// The byte that says which this is, and which the channel authenticates as its context.
    public var kind: UInt8 {
        switch self {
        case .envelope: FrameCodec.envelopeKind
        case .chunk: FrameCodec.chunkKind
        }
    }
}
