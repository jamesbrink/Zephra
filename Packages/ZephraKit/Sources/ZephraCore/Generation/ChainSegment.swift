import Foundation

/// Which pass of a chained clip a queued generation is, and which chain it belongs to.
public struct ChainSegment: Hashable, Sendable {
    /// The chain, one per clip asked for.
    public let chainID: UUID
    /// This segment's place, counting from zero.
    public let index: Int
    /// How many segments the chain has.
    public let count: Int

    public init(chainID: UUID, index: Int, count: Int) {
        self.chainID = chainID
        self.index = index
        self.count = count
    }

    /// Whether this is the segment the chain ends on.
    public var isLast: Bool { index + 1 >= count }
}
