import Foundation
import ZephraCore

/// One square in a run: an image the library has indexed, or an image this session has just
/// made.
///
/// Two cases because there are two sources and they arrive at different speeds. `LibraryIndex`
/// lags `GenerationStore.history` by a debounced folder scan, so an image that has just landed
/// is a `.fresh` tile for the second or so before the index catches up and the same square
/// becomes an `.item`. Both sit at the same position in the run, so a square is filled in place
/// rather than the row shuffling under the pointer. The wall holds finished pictures only: a
/// seed still to come has no tile at all.
public enum TimelineTile: Identifiable, Hashable, Sendable {
    /// An image the library index knows about, which is what every tile settles into.
    case item(LibraryItem)
    /// An image this session made, before the index has seen the file.
    case fresh(GeneratedImage)

    /// Stable within its own run, which is the only place tiles are ever listed together.
    public var id: String {
        switch self {
        case .item(let item): "item:\(item.id)"
        case .fresh(let image): "fresh:\(image.id.uuidString)"
        }
    }

    /// The file the tile stands for.
    public var fileURL: URL? {
        switch self {
        case .item(let item): item.url
        case .fresh(let image): image.fileURL
        }
    }
}
