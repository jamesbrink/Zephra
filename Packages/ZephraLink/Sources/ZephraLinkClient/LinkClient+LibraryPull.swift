import Foundation
import ZephraLinkProtocol
import ZephraLinkTransport

/// Reading the Mac's library across, a page at a time, after every connect.
///
/// The Mac publishes what *changed* in its folder and counts the folder in the snapshot; it
/// never sends the folder. Nothing changing on the Mac therefore means nothing arriving, which
/// is what left a freshly paired phone with a full Today tab and an empty grid: the deltas were
/// working exactly as written, and there were none. The pull is the other half of that bargain —
/// the phone asks for what it was never told — and it is the phone's alone, so a Mac that is
/// already shipped needs no change to answer it.
///
/// One page is in flight at a time and nothing here touches the Mac's store, so the loop keeps
/// going while the Mac is generating: `libraryPage` is read off the index the phone can already
/// see, and a request that waits its turn behind a step is a page that arrives a moment later
/// rather than a run that stutters.
extension LinkClient {
    /// How many entries one page asks for.
    ///
    /// The Mac's own reset threshold, and comfortably under its 200 clamp: small enough that the
    /// first page is on screen almost at once, large enough that a library of a few thousand is
    /// a few dozen round trips rather than a few hundred.
    public static let libraryPageSize = 100

    /// Starts the pull again, from the top.
    ///
    /// Called wherever a snapshot lands, which is every connect: a listing may have moved while
    /// the phone was away, and the snapshot is the one frame that says a session is up.
    func startLibraryPull() {
        guard !isFrozen else { return }
        libraryPull?.cancel()
        libraryIsComplete = false
        libraryPull = Task { [weak self] in await self?.pullLibrary() }
    }

    /// Stops it, wherever a session ends. The next snapshot starts a new one.
    func endLibraryPull() {
        libraryPull?.cancel()
        libraryPull = nil
    }

    /// The loop: one page, applied, then the next, until the offset reaches the total.
    ///
    /// `nonisolated`, so the waiting between pages is nobody's main actor; the only thing that
    /// runs there is `absorb`, which is the one mutation. The total is re-read from every page
    /// rather than taken once from the snapshot, because the folder may move underneath a pull
    /// that takes a few seconds. A page that answers no entries stops it — there is no offset to
    /// advance to — but only a page whose own total was reached says the listing is complete.
    private nonisolated func pullLibrary() async {
        var offset = 0
        var failures = 0
        while !Task.isCancelled {
            do {
                let page = try await libraryPage(offset: offset, limit: Self.libraryPageSize)
                failures = 0
                let next = page.offset + page.entries.count
                await absorb(page, complete: next >= page.total)
                guard next > offset, next < page.total else { return }
                offset = next
            } catch {
                // A refusal or a timeout is not the end of the pull: the Mac may have been busy
                // or a road may have hiccuped, and the offset is still the right one to ask for.
                // A session that has actually gone is, since the next one starts its own pull.
                guard await connection.isLive else { return }
                failures += 1
                guard (try? await Task.sleep(for: LinkBackoff.delay(after: failures))) != nil
                else { return }
            }
        }
    }

    /// One page into `library`, and whether that was the last of them, in one step.
    ///
    /// Both together because a cache applies its removals on the strength of the flag, and a
    /// turn of the main actor between the entries landing and the flag rising is a turn where
    /// the whole library looks present and incomplete.
    ///
    /// An entry the phone has not got is **appended**, where `LibraryChange.upserted` puts one
    /// at the front: the pages arrive newest first, so the front is where the page before it
    /// already is. The list is rebuilt once and assigned once, so a page is one observation and
    /// not a hundred.
    @MainActor
    private func absorb(_ page: LibraryPage, complete: Bool) {
        var entries = library
        var places = Dictionary(
            entries.enumerated().map { ($0.element.fileName, $0.offset) },
            uniquingKeysWith: { first, _ in first })
        for entry in page.entries {
            if let place = places[entry.fileName] {
                entries[place] = entry
            } else {
                places[entry.fileName] = entries.count
                entries.append(entry)
            }
        }
        library = entries
        if complete { libraryIsComplete = true }
    }
}
