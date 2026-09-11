import CryptoKit
import Foundation
import ZephraEngine

/// One picture in the library, as the phone holds it.
///
/// The record and the annotation are the real types out of the PNG's two text chunks, not
/// copies of their fields: the folder is the truth, and a second shape of that truth on the
/// wire is a second thing to keep in step. The version is what lets the phone cache: an entry
/// whose version has not moved is a file whose bytes have not moved, so a thumbnail already
/// fetched is still the right one.
public struct LibraryEntry: Codable, Hashable, Sendable, Identifiable {
    /// The file's name inside the library folder, which is its identity everywhere in the
    /// protocol: no absolute paths cross, for the reason no record holds one.
    public var fileName: String
    /// A short fingerprint of the file as it stands, for caching.
    public var version: String
    /// What produced the picture, or nil for a file Zephra did not make.
    public var record: GenerationRecord?
    /// What the user has said about it.
    public var annotation: LibraryAnnotation
    /// Whether the picture is a clip's poster.
    public var isVideo: Bool
    /// When it was made.
    public var createdAt: Date
    /// Pixels across.
    public var width: Int
    /// Pixels down.
    public var height: Int
    /// How many bytes the file is.
    public var fileSize: Int
    /// When the file last changed on disk.
    public var contentModifiedAt: Date

    /// The file's name is its identity.
    public var id: String { fileName }

    /// Creates an entry. The version is computed from the name, the time and the size unless
    /// one is passed, so the rule has one home.
    public init(
        fileName: String,
        record: GenerationRecord?,
        annotation: LibraryAnnotation,
        isVideo: Bool,
        createdAt: Date,
        width: Int,
        height: Int,
        fileSize: Int,
        contentModifiedAt: Date,
        version: String? = nil
    ) {
        self.fileName = fileName
        self.record = record
        self.annotation = annotation
        self.isVideo = isVideo
        self.createdAt = createdAt
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.contentModifiedAt = contentModifiedAt
        self.version = version
            ?? Self.version(
                fileName: fileName, contentModifiedAt: contentModifiedAt, fileSize: fileSize)
    }

    /// The fingerprint of one file: the first sixteen hex digits of the SHA-256 of its name,
    /// its modification time and its size.
    ///
    /// The same three facts `LibraryScan` re-reads a file on, so an entry's version moves
    /// exactly when the Mac thinks the file moved. Truncated to eight bytes because it is a
    /// cache key rather than a security claim, and a short one keeps a page of a thousand
    /// entries small.
    public static func version(fileName: String, contentModifiedAt: Date, fileSize: Int) -> String {
        let stamp = Self.stamps.format(contentModifiedAt)
        let digest = SHA256.hash(data: Data("\(fileName)\(stamp)\(fileSize)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// One spelling of a date, so the same file fingerprints the same on both ends.
    ///
    /// The format style rather than `ISO8601DateFormatter`: a value a `static let` can hold
    /// under strict concurrency, where the formatter is a class with shared mutable state.
    /// Fractional seconds, so a file rewritten inside one second still changes its version.
    private static let stamps = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
