import Foundation
import ZephraLinkProtocol

/// The commands a view calls, each one a request whose refusal is thrown rather than returned.
extension LinkClient {
    /// Queues a press of Generate and answers the run it made.
    ///
    /// A reference picture goes first, as a blob, and the request names it: megabytes of PNG
    /// inside a JSON envelope would block the channel for everything else, previews included.
    @discardableResult
    public func enqueue(_ request: GenerationRequest, reference: Data? = nil) async throws -> UUID {
        var outgoing = request
        if let reference {
            let blobID = try await sendBlob(reference, mime: "image/png")
            // The request keeps its own id: a retry has to look like the same press of Generate
            // to the Mac, whatever the envelope around it is called.
            outgoing = GenerationRequest(
                modelID: request.modelID, count: request.count, settings: request.settings,
                referenceBlobID: blobID, requestID: request.requestID)
        }
        switch try await self.request(.enqueue(outgoing)) {
        case .queued(let batchID): return batchID
        case .error(let error): throw error
        case .multiHost, .ok, .blob, .entries: throw LinkClientError.unexpectedReply
        }
    }

    /// One picture's thumbnail, `pixels` on its long edge.
    public func thumbnail(name: String, pixels: Int) async throws -> Data {
        try await transferAdmission.enter(transferOwner)
        defer { transferAdmission.leave(transferOwner) }
        return try await fetchBlob(.fetchThumbnail(name: name, pixels: pixels))
    }

    /// One picture's file, or a clip's MP4.
    public func file(name: String) async throws -> Data {
        try await transferAdmission.enter(transferOwner)
        defer { transferAdmission.leave(transferOwner) }
        return try await fetchBlob(.fetchFile(name: name))
    }

    /// One window onto the library.
    public func libraryPage(offset: Int, limit: Int) async throws -> LibraryPage {
        switch try await request(.libraryPage(offset: offset, limit: limit)) {
        case .entries(let page): return page
        case .error(let error): throw error
        case .multiHost, .ok, .queued, .blob: throw LinkClientError.unexpectedReply
        }
    }

    /// Marks pictures as favorites, or unmarks them.
    public func setFavourite(names: [String], on: Bool) async throws {
        try await perform(.setFavourite(names: names, on: on))
    }

    /// Replaces the tags on pictures.
    public func setTags(names: [String], tags: [String]) async throws {
        try await perform(.setTags(names: names, tags: tags))
    }

    /// Moves pictures to Recently Deleted.
    public func delete(_ names: [String]) async throws {
        try await perform(.delete(names))
    }

    /// Stops whatever is running.
    public func cancel() async throws {
        try await perform(.cancel)
    }

    /// Chooses another model.
    public func switchModel(_ modelID: String) async throws {
        try await perform(.switchModel(modelID))
    }

    /// A command whose only good answer is that it was done.
    private func perform(_ command: Command) async throws {
        switch try await request(command) {
        case .multiHost, .ok, .queued, .blob, .entries: return
        case .error(let error): throw error
        }
    }
}
