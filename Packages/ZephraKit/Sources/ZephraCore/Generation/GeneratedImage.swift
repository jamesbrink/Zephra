import Foundation

/// A finished image together with the settings that produced it, so it can be reproduced.
public struct GeneratedImage: Identifiable, Hashable, Sendable {
    /// Identity within a session, assigned when the image is created.
    public let id: UUID
    /// The encoded PNG bytes.
    public let pngData: Data
    /// The exact settings the backend ran.
    public let settings: GenerationSettings
    /// The model that produced it, as a `ModelDescriptor` identifier.
    public let modelID: String
    /// When generation finished.
    public let createdAt: Date
    /// How long the whole generation took.
    public let duration: Duration
    /// Where the bytes were written, once they have been saved.
    public private(set) var fileURL: URL?
    /// Which press of Generate produced it, when it was one of several seeds, and nil otherwise.
    ///
    /// Written into the file's own record as well, so a run outlives the session that made it:
    /// the session timeline groups by this, and an image read back after a relaunch would
    /// otherwise be a run of one. A file written before the field existed has no batch, which
    /// is why the timeline can also group by adjacency.
    public let batchID: UUID?

    /// Creates a record of a finished image.
    public init(
        id: UUID = UUID(),
        pngData: Data,
        settings: GenerationSettings,
        modelID: String,
        createdAt: Date = Date(),
        duration: Duration,
        fileURL: URL? = nil,
        batchID: UUID? = nil
    ) {
        self.id = id
        self.pngData = pngData
        self.settings = settings
        self.modelID = modelID
        self.createdAt = createdAt
        self.duration = duration
        self.fileURL = fileURL
        self.batchID = batchID
    }

    /// A copy that knows where it now lives on disk.
    public func withFileURL(_ url: URL?) -> GeneratedImage {
        var copy = self
        copy.fileURL = url
        return copy
    }
}
