import CoreTransferable
import Foundation

/// One tile of the reference strip on its way to another place in the same strip: its position,
/// and nothing else.
///
/// A drag inside the strip is a reorder, and the order is what the model reads the pictures in,
/// so it is a choice rather than a presentation. The payload is the index it started at; the
/// tile it lands on works out where that is relative to itself and asks the store to move it.
///
/// A type of its own rather than `LibraryItemReference`, for the reason that one exists: a
/// picture dragged out of the library is a *new* reference and a tile dragged along the strip is
/// an existing one moving, and a `dropDestination` that could not tell them apart would file one
/// as the other. Two types, two destinations, and neither drop is ambiguous.
struct ReferenceSlotReference: Codable, Transferable, Hashable {
    /// Where in the strip the picture being dragged sits now.
    let index: Int

    nonisolated static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .zephraReferenceSlot)
    }
}
