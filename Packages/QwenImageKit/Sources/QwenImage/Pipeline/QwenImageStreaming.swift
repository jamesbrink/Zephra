/// How to stream the weights from disk instead of holding them.
///
/// Handed to `QwenImagePipeline.loadModel` by a host whose Mac cannot hold the model: the text
/// encoder's layers and the transformer's blocks are then read from their shards on every pass,
/// `depth` layers ahead of the one running, and nothing but a window of them is ever in memory.
public struct QwenImageStreaming: Hashable, Sendable {
    /// Layers read ahead of the one running. Two holds three layers at once, which at 269 MB
    /// a block is under a gigabyte, and is enough to keep the disk ahead of the GPU.
    public var depth: Int

    public init(depth: Int = 2) {
        self.depth = max(0, depth)
    }
}
