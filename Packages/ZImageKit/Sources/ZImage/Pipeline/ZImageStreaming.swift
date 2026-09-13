// ZEPHRA-PATCH: streaming the weights from disk, so a Mac that cannot hold this model still
// runs it. New file; the mechanism is `ZephraMLX.LayerWeightStream` and this is only what a
// host asks for. See VENDORED.md.
import Foundation

/// How to stream the weights from disk instead of holding them.
///
/// Handed to `ZImagePipeline.loadModel` by a host whose Mac cannot hold the model: the text
/// encoder's layers and the transformer's three block stacks are then read from their shards on
/// every pass, `depth` layers ahead of the one running, and nothing but a window of them is ever
/// in memory. The cost is one read of the model per step.
public struct ZImageStreaming: Hashable, Sendable {
  /// Layers read ahead of the one running. Two holds three layers at once, which is enough to
  /// keep the disk ahead of the GPU without giving back what streaming bought.
  public var depth: Int

  public init(depth: Int = 2) {
    self.depth = max(0, depth)
  }
}
