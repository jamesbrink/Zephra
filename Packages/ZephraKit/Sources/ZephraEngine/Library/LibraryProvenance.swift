import Foundation

/// Where a file in the library came from: Zephra made it, or somebody brought it in.
///
/// A library item is one or the other and never both, which is what keeps the grid honest about
/// what it can offer. Only a generated image has a prompt to show or a seed to vary; only an
/// imported one has an original file name worth reading.
public enum LibraryProvenance: Hashable, Sendable {
    /// Zephra made it, and this is what it was asked for.
    case generated(GenerationRecord)
    /// It was imported to generate from, and this is where it came from.
    case imported(SourceRecord)

    /// The generation record, or nil for an imported picture.
    public var record: GenerationRecord? {
        guard case .generated(let record) = self else { return nil }
        return record
    }

    /// The import record, or nil for an image Zephra made.
    public var source: SourceRecord? {
        guard case .imported(let source) = self else { return nil }
        return source
    }

    /// When the file came to exist: when the generation finished, or when the picture was
    /// imported. The library sorts and groups by this rather than by the file system's dates,
    /// so images copied in from another Mac sit where they belong.
    public var createdAt: Date {
        switch self {
        case .generated(let record): record.createdAt
        case .imported(let source): source.importedAt
        }
    }
}
