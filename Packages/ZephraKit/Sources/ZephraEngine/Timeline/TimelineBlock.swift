import Foundation

/// One stretch of the sidebar's wall: a run that stands on its own, or several runs of one
/// picture packed together.
///
/// The wall is dense because single pictures share rows, and legible because a batch does not.
/// A block is the unit that makes both true at once: `SessionTimeline.blocks(of:)` says which
/// runs get one to themselves.
public struct TimelineBlock: Identifiable, Hashable, Sendable {
    /// The id of the run this block is, or of the newest run in it when it holds several. A
    /// single that later gains company keeps the block's id, so the wall does not rebuild.
    public let id: UUID
    /// The squares, in the order the runs are listed and, within a run, oldest first.
    public let tiles: [TimelineTile]

    /// Describes one block. Built by `SessionTimeline`; there is no other caller.
    public init(id: UUID, tiles: [TimelineTile]) {
        self.id = id
        self.tiles = tiles
    }
}
