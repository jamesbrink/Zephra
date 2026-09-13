import Foundation
import ZephraLinkProtocol
import ZephraLinkTransport

extension LinkClient {
    public static let libraryPageSize = 100

    func startLibraryPull() {
        guard !isFrozen else { return }
        if let progress = libraryProgress, progress.total == snapshot?.libraryCount { return }
        endLibraryPull()
        libraryIsComplete = false
        libraryPull = Task { [weak self] in await self?.readEveryPage() }
    }
    func endLibraryPull() {
        libraryPull?.cancel()
        libraryPull = nil
        libraryProgress = nil
    }

    /// Pages are staged privately. A library delta during the pull invalidates the entire pass.
    /// Legacy offsets are verified by two identical full passes before cache pruning is allowed.
    private func readEveryPage() async {
        var offset = 0
        var failures = 0
        var revision: String?
        var collected: [LibraryEntry] = []
        var prior: [LibraryEntry]?
        var mutation = libraryMutation
        defer { if !Task.isCancelled { libraryProgress = nil; libraryPull = nil } }
        while !Task.isCancelled {
            do {
                let modern = supportsMultiHost
                let page: LibraryPage
                if modern {
                    let result = try await listing(offset: offset, revision: revision)
                    revision = result.revision
                    page = result.page
                } else { page = try await libraryPage(offset: offset, limit: Self.libraryPageSize) }
                guard !Task.isCancelled else { return }
                if mutation != libraryMutation {
                    offset = 0; revision = nil; collected = []; prior = nil
                    mutation = libraryMutation
                    continue
                }
                guard page.offset == offset, !page.entries.isEmpty || offset >= page.total else {
                    throw LinkClientError.unexpectedReply
                }
                collected.append(contentsOf: page.entries)
                let next = offset + page.entries.count
                libraryProgress = LibraryPullProgress(offset: next, total: page.total)
                // Publish upserts early, but never call an incomplete listing authoritative.
                var held = Dictionary(library.map { ($0.fileName, $0) }, uniquingKeysWith: { _, last in last })
                for entry in page.entries { held[entry.fileName] = entry }
                library = held.values.sorted { $0.createdAt > $1.createdAt }
                if next >= page.total {
                    if modern || prior == collected {
                        library = collected
                        libraryIsComplete = true
                        return
                    }
                    prior = collected; collected = []; offset = 0
                } else { offset = next }
                failures = 0
            } catch {
                guard !Task.isCancelled, connection.isLive else { return }
                failures += 1
                if supportsMultiHost {
                    offset = 0; revision = nil; collected = []; prior = nil; mutation = libraryMutation
                }
                do { try await Task.sleep(for: LinkBackoff.delay(after: failures)) } catch { return }
            }
        }
    }
}
