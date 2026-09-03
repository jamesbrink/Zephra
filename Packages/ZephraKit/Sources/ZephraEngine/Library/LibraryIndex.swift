import Foundation
import Observation

/// The library as the interface sees it: every image on disk, the query narrowing them, and the
/// sections that come out of the two.
///
/// The one observable object the sidebar, the grid and the inspector share, and the only place
/// that knows the disk is a disk. It holds no truth of its own — everything here can be rebuilt
/// by rescanning the folder, which is what lets a change made in the Finder be right rather than
/// merely noticed.
///
/// Mutations are optimistic: the grid changes at once, the write is queued behind whatever else
/// is queued, and a write that fails puts the one image back from what is actually on disk.
@MainActor
@Observable
public final class LibraryIndex {
    /// Every image in every collection, newest first.
    public internal(set) var items: [LibraryItem] = []
    /// What `query` names, grouped into days. Recomputed whenever either side changes.
    public internal(set) var sections: [LibrarySection] = []
    /// The albums that exist, in the order a sidebar should list them.
    public internal(set) var albums: [Album] = []
    /// The numbers beside the sidebar's rows.
    public internal(set) var counts: LibraryCounts = .empty
    /// Every tag in use, sorted, for the tag popover and the sidebar.
    public internal(set) var allTags: [String] = []
    /// True while a scan is running. A scan never blocks anything; this is for a spinner.
    public internal(set) var isScanning = false
    /// The most recent thing the library could not do, or nil when the last one worked.
    public internal(set) var lastFailure: LibraryFailure?
    /// What the library is showing. Setting it reprojects; it never rescans.
    public var query: LibraryQuery {
        didSet {
            guard query != oldValue else { return }
            reproject()
        }
    }

    /// The folders being indexed.
    public let library: ImageLibrary

    let scan: LibraryScan
    /// How long the folder watch waits for things to stop moving before it looks. Injectable
    /// because a test cannot wait a quarter of a second per assertion.
    let settleFor: Duration

    /// The one chain every write goes down, so two mutations never touch a file at once.
    @ObservationIgnored var work: Task<Void, Never>?
    /// Annotations written optimistically and not yet on disk, coalesced by file: a favourite
    /// toggled five times before the first write lands is one write.
    @ObservationIgnored var pending: [LibraryItem.ID: LibraryAnnotation] = [:]
    @ObservationIgnored var watches: [LibraryCollection: LibraryFolderWatch] = [:]
    @ObservationIgnored var debounce: Task<Void, Never>?
    @ObservationIgnored var fingerprint = 0
    /// How many scans have actually read the folders, which is what proves the fingerprint is
    /// doing its job.
    @ObservationIgnored var scanCount = 0
    @ObservationIgnored var hasStarted = false
    /// False for the preview index, which has no folder and must never look for one.
    @ObservationIgnored var isLive = true

    /// An index over one library's folders. Nothing is read until `start()`.
    public init(
        library: ImageLibrary,
        query: LibraryQuery = LibraryQuery(),
        settleFor: Duration = .milliseconds(200),
        calendar: Calendar = .current
    ) {
        self.library = library
        self.query = query
        self.settleFor = settleFor
        self.scan = LibraryScan(library: library, calendar: calendar)
    }

    /// One image by its path, which is what a selection is a set of.
    public func item(for id: LibraryItem.ID) -> LibraryItem? {
        items.first { $0.id == id }
    }

    /// How many images another query would show, for a sidebar row that is not the current one.
    /// Counting, not listing: the order of the matches is nobody's business here.
    public func count(for query: LibraryQuery) -> Int {
        items.lazy.filter { query.matches($0) }.count
    }

    /// Recomputes everything derived from `items`, `albums` and `query`. The one place that
    /// happens, so nothing on screen can disagree with anything else.
    func reproject() {
        sections = query.sections(of: items)
        counts = LibraryCounts(items: items, albumIDs: albums.map(\.id))
        allTags = Set(items.flatMap(\.tags)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    /// Waits for every queued write and rescan. A seam for tests, which need the disk to have
    /// caught up before they assert.
    func settle() async {
        await work?.value
    }
}
