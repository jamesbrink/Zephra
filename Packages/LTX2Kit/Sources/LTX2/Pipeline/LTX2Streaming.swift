import Foundation

/// How a streamed load reads the two layer stacks: the number of layers read ahead of the one
/// running. Two holds three layers of each stack at once.
public struct LTX2Streaming: Hashable, Sendable {
    public var depth: Int

    public init(depth: Int = 2) {
        self.depth = depth
    }
}
