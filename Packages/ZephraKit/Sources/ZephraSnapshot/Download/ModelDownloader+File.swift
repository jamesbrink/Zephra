import Foundation
import ZephraCore

extension ModelDownloader {
    /// Fetches one file, continuing from whatever of it is already on disk.
    ///
    /// The order of the checks is the whole of it. A file already in place at the listed size
    /// is left alone. Otherwise the `.incomplete` beside it says where to resume from, sent as
    /// a `Range`; a server that answers 200 to that has ignored it, so what is there is thrown
    /// away and the file starts over rather than being spliced onto the wrong offset. The
    /// rename happens only once the size matches, so a transfer that ends early stays an
    /// `.incomplete` and the next try picks it up.
    func fetch(
        _ file: RepositoryFile,
        from repoID: String,
        revision: String,
        into destination: URL,
        on session: URLSession,
        tally: inout DownloadTally,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws {
        let target = destination.appending(path: file.path)
        if let size = Self.size(of: target), file.bytes == 0 || size == file.bytes { return }
        let partial = Self.partial(of: target)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        var have = Self.size(of: partial) ?? 0
        if file.bytes > 0, have > file.bytes {
            // Longer than the listing says it should be: this is not the file it was, and the
            // bytes are worth nothing.
            try? FileManager.default.removeItem(at: partial)
            tally.discard(have)
            have = 0
        }
        if file.bytes > 0, have == file.bytes {
            try replace(partial, with: target)
            return
        }

        let url = host.appending(path: "\(repoID)/resolve/\(revision)/\(file.path)")
        var request = request(url)
        if have > 0 { request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
        let delegate = session.delegate as? ChunkedDownload
        guard let delegate else {
            throw ModelDownloadError.interrupted(reason: "The download session was not set up.")
        }
        let response: HTTPURLResponse
        let chunks: ChunkedBody
        do {
            (response, chunks) = try await delegate.start(request, on: session)
        } catch {
            // A stopped transfer arrives as the session's own "cancelled" error, and a person
            // who pressed Stop is not owed four more attempts.
            try Task.checkCancellation()
            throw ModelDownloadError.interrupted(reason: error.localizedDescription)
        }
        switch response.statusCode {
        case 206: break
        case 200:
            // The server sent the file whole. Anything already written is at the wrong offset.
            if have > 0 {
                tally.discard(have)
                have = 0
            }
            try? FileManager.default.removeItem(at: partial)
        case 404: throw ModelDownloadError.fileNotFound(path: file.path)
        case 400..<500:
            throw ModelDownloadError.refused(status: response.statusCode, path: file.path)
        default:
            throw ModelDownloadError.interrupted(
                reason: "Hugging Face answered HTTP \(response.statusCode) for \(file.path).")
        }

        try await write(chunks, to: partial, tally: &tally, onProgress: onProgress)
        let written = Self.size(of: partial) ?? 0
        guard file.bytes == 0 || written == file.bytes else {
            throw ModelDownloadError.interrupted(
                reason: "\(file.path) ended early, at \(written) bytes of \(file.bytes).")
        }
        try replace(partial, with: target)
    }

    /// Appends the body to `partial` as it arrives, checking between chunks so a person who
    /// pressed Stop is not waiting on the rest of a twelve-gigabyte shard.
    private func write(
        _ chunks: ChunkedBody,
        to partial: URL,
        tally: inout DownloadTally,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws {
        let files = FileManager.default
        if !files.fileExists(atPath: partial.path(percentEncoded: false)) {
            files.createFile(atPath: partial.path(percentEncoded: false), contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        try handle.seekToEnd()
        do {
            for try await chunk in chunks {
                try Task.checkCancellation()
                try handle.write(contentsOf: chunk)
                tally.advance(by: Int64(chunk.count))
                if let event = tally.report() { onProgress(event) }
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as ModelDownloadError {
            throw error
        } catch {
            try Task.checkCancellation()
            throw ModelDownloadError.interrupted(reason: error.localizedDescription)
        }
        try handle.synchronize()
    }

    /// Puts the finished file in place, over whatever was there.
    private func replace(_ partial: URL, with target: URL) throws {
        let files = FileManager.default
        if files.fileExists(atPath: target.path(percentEncoded: false)) {
            try files.removeItem(at: target)
        }
        try files.moveItem(at: partial, to: target)
    }
}
