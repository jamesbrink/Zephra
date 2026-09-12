import Foundation
import ZephraEngine
import ZephraLinkProtocol

/// The commands that are about files: what the user has said about a picture, sending one
/// across, and reading a window onto the folder.
///
/// Every annotation edit is made with the index's undo manager lifted off and put back. Undo on
/// the Mac is the Edit menu of the window in front of the person sitting at it; a favourite a
/// phone toggled appearing there as "Undo Favorite" would be an edit they never made and cannot
/// see, sitting on top of the one they did.
extension CompanionSession {
    /// The file commands. Called from `perform`, which has already answered the rest.
    func performLibrary(
        _ command: Command, id: UUID, on host: CompanionHost
    ) async throws -> Reply? {
        switch command {
        case .setFavourite(let names, let on):
            let ids = try identifiers(for: names)
            withoutUndo(host.index) { $0.setFavourite(ids, on: on) }
            return .ok
        case .setTags(let names, let tags):
            let ids = try identifiers(for: names)
            withoutUndo(host.index) { $0.setTags(tags, on: ids) }
            return .ok
        case .delete(let names):
            host.index.moveToRecentlyDeleted(try identifiers(for: names))
            return .ok
        case .fetchThumbnail(let name, let pixels):
            try await sendThumbnail(name, pixels: pixels, from: host, to: id)
            return nil
        case .fetchFile(let name, let fromChunk):
            try await sendFile(name, to: id, from: fromChunk)
            return nil
        case .libraryPage(let offset, let limit):
            let items = LibraryEntryProjection.listing(host.index.items)
            return .entries(
                LibraryEntryProjection.page(items, offset: offset, limit: min(max(limit, 0), 200)))
        default:
            throw LinkError(code: .unsupported, reason: "This Mac does not do that yet.")
        }
    }

    /// One picture, small, as JPEG.
    private func sendThumbnail(
        _ name: String, pixels: Int, from host: CompanionHost, to request: UUID
    ) async throws {
        let item = try item(named: name)
        guard let data = await host.thumbnails.thumbnail(for: item.url, pixels: max(pixels, 1))
        else {
            throw LinkError(code: .notFound, reason: "That picture could not be read.")
        }
        try sendBlob(data, mime: "image/jpeg", to: request)
    }

    /// The file itself: a clip's MP4 where there is one, the PNG otherwise, read off the main
    /// actor because it may be tens of megabytes.
    ///
    /// `from` is where the phone got to on an earlier attempt. The whole file is still read and
    /// still announced whole; only the chunks before that are left out, so asking again for the
    /// same file answers with the same bytes however far in it starts.
    private func sendFile(_ name: String, to request: UUID, from: UInt32 = 0) async throws {
        let item = try item(named: name)
        let url = item.videoURL.flatMap {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) ? $0 : nil
        } ?? item.url
        guard let data = await Task.detached(priority: .utility, operation: {
            try? Data(contentsOf: url)
        }).value else {
            throw LinkError(code: .notFound, reason: "That file could not be read.")
        }
        try sendBlob(
            data, mime: VideoSidecar.isSidecar(url) ? "video/mp4" : "image/png", to: request,
            from: from)
    }

    /// The picture one file name means, or a refusal naming it.
    func item(named name: String) throws -> LibraryItem {
        guard let item = host?.index.item(named: name) else {
            throw LinkError(code: .notFound, reason: "This Mac has no picture called \(name).")
        }
        return item
    }

    /// Several names as the ids a mutation takes. One unknown name refuses the whole request:
    /// a partial edit the phone was never told about is worse than none.
    private func identifiers(for names: [String]) throws -> Set<LibraryItem.ID> {
        guard !names.isEmpty else {
            throw LinkError(code: .badRequest, reason: "Name at least one picture.")
        }
        return Set(try names.map { try item(named: $0).id })
    }

    /// Runs one index mutation with the undo manager off, and puts it back whatever happens.
    private func withoutUndo(_ index: LibraryIndex, _ change: (LibraryIndex) -> Void) {
        let manager = index.undoManager
        index.undoManager = nil
        defer { index.undoManager = manager }
        change(index)
    }
}
