import Foundation
import ZephraEngine

/// One finished picture this session made.
///
/// The record is `GenerationRecord` itself, not a copy of its fields. That record is the truth
/// inside the PNG and it is already `Codable`; mirroring it here would give the same provenance
/// two shapes that could drift apart, and the phone needs the same fields the inspector shows.
public struct HistoryEntry: Codable, Hashable, Sendable, Identifiable {
    /// This session's handle on the picture.
    public var id: UUID
    /// The file it was written as, or nil before it has been written.
    public var fileName: String?
    /// What produced it.
    public var record: GenerationRecord
    /// Whether the picture is a clip's poster.
    public var isVideo: Bool

    /// Creates a history row.
    public init(id: UUID, fileName: String?, record: GenerationRecord, isVideo: Bool) {
        self.id = id
        self.fileName = fileName
        self.record = record
        self.isVideo = isVideo
    }

    /// A row whose `isVideo` follows the record, which is the only thing that says so.
    public init(id: UUID, fileName: String?, record: GenerationRecord) {
        self.init(id: id, fileName: fileName, record: record, isVideo: record.isVideo)
    }
}
