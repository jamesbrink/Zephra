import Foundation

/// A named set of images, held by identity rather than by name.
///
/// The id is what an image records, so renaming an album rewrites one small JSON file and not
/// every picture in it. The name in each image's annotation is a copy kept for the case where
/// the manifest is gone, and the manifest is what wins when the two disagree.
public struct Album: Identifiable, Hashable, Sendable, Codable {
    /// Stable identity, which a rename does not change.
    public let id: UUID
    /// What the album is called.
    public var name: String
    /// When it was made, which is what orders albums made in the same breath.
    public let createdAt: Date

    /// Creates an album. The id and the date are made here unless a manifest is handing back
    /// ones it already had.
    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
