import Foundation
import ZephraLinkProtocol

/// What the sessions have already been told, so the observation loop publishes only what moved.
///
/// A record of the last projection rather than a second copy of the state: nothing here is read
/// by anything but the comparison in `CompanionHost+Observation`, and every field is exactly
/// what one `StateDelta` case carries. The library is kept as versions by file name rather than
/// as entries, because that is the whole of what a change means — `LibraryEntry.version` moves
/// exactly when the Mac thinks the file moved.
struct CompanionPublication {
    /// False until the first pass, when everything is new and nothing is a change.
    var hasPublished = false
    var engine: EngineStateDTO?
    var queue: [QueuedEntry] = []
    var running: QueuedEntry?
    /// This session's pictures by identity, so an insert and a removal are a set difference.
    var history: [UUID] = []
    var modelID: String?
    var availability: [String: AvailabilityDTO] = [:]
    var downloads: [DownloadDTO] = []
    var today: [RunSummary] = []
    var libraryVersions: [String: String] = [:]
    var acceptsWork: Bool?
    /// A cheap fingerprint of the last frame sent, since `GenerationPreview` is deliberately not
    /// `Equatable` — hashing a quarter of a megabyte ten times a second is the cost it avoids.
    var previewFingerprint: Data?
    /// When that frame went, for the throttle.
    var previewSentAt: ContinuousClock.Instant?

    /// How many library entries a change may carry before the phone is told to start again.
    ///
    /// A folder scanned wholesale — a first launch, a changed images folder, a thousand files
    /// copied in — is a reset rather than a diff, for the reason `LibraryChange` says: a phone
    /// holds a page at a time, and a diff of a thousand entries is larger than the window it is
    /// looking at.
    static let resetThreshold = 100
}
