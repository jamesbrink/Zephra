import Foundation

/// How a streamed load reads the two layer stacks: the number of layers read ahead of the one
/// running. Two holds three layers of each stack at once.
///
/// The stacks are the transformer's 32 blocks and the text encoder's 36 decoder layers. The
/// vision tower and the autoencoder never stream: the tower runs once per reference picture and
/// the autoencoder once per generation, and between them they are a fraction of what the two
/// stacks hold.
public struct QwenImage21Streaming: Hashable, Sendable {
    /// Layers read ahead of the one running.
    public var depth: Int

    public init(depth: Int = 2) {
        self.depth = depth
    }
}
