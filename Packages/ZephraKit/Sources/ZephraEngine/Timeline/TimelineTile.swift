import Foundation
import ZephraCore

/// One square in a run: an image the library has indexed, an image this session has just made,
/// or a place still to be filled.
///
/// Three cases because there are three sources and they arrive at different speeds.
/// `LibraryIndex` lags `GenerationStore.history` by a debounced folder scan, so an image that
/// has just landed is a `.fresh` tile for the second or so before the index catches up and the
/// same square becomes an `.item`. The place it takes was a `.pending` tile before that. All
/// three sit at the same position in the run, so a square is filled in place rather than the
/// row shuffling under the pointer.
public enum TimelineTile: Identifiable, Hashable, Sendable {
    /// An image the library index knows about, which is what every tile settles into.
    case item(LibraryItem)
    /// An image this session made, before the index has seen the file.
    case fresh(GeneratedImage)
    /// A seed of this run that has not produced an image yet, at its place in the run.
    case pending(Int)

    /// Stable within its own run, which is the only place tiles are ever listed together.
    ///
    /// A pending tile is identified by the seed's index rather than by anything about the run,
    /// because a run draws its own tiles and never draws another run's.
    public var id: String {
        switch self {
        case .item(let item): "item:\(item.id)"
        case .fresh(let image): "fresh:\(image.id.uuidString)"
        case .pending(let index): "pending:\(index)"
        }
    }

    /// The file the tile stands for, once there is one. Nil for a place still to be filled.
    public var fileURL: URL? {
        switch self {
        case .item(let item): item.url
        case .fresh(let image): image.fileURL
        case .pending: nil
        }
    }
}
