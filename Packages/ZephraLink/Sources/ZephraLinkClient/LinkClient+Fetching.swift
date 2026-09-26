import Foundation
import ZephraLinkProtocol
import ZephraLinkTransport

/// Asking the Mac for bytes, and asking again for the part of them that never arrived.
extension LinkClient {
    /// A command whose answer is bytes: the reply announces the blob and the chunks follow.
    ///
    /// A transfer a hole in the stream swallowed is asked for again, up to `blobAttempts` times
    /// and **from where it got to**. The announcement is answered before its chunks, so
    /// `request`'s own retry cannot cover this half: the reply arrived and it is the bytes behind
    /// it that went missing. And over the relay a whole picture is ninety-odd chunks and a clip
    /// two and a half thousand, so asking for the whole file again on every hole meant a large
    /// clip finished only by luck — each attempt got as far as the next lost frame.
    ///
    /// The wait between attempts is `LinkBackoff`'s, because a road that has just lost a frame is
    /// a road worth giving a moment.
    public func fetchBlob(_ command: Command) async throws -> Data {
        guard !isFrozen else { throw LinkClientError.notConnected }
        var reservations: Set<UUID> = []
        defer { for id in reservations { blobBudget.release(owner: transferOwner, blob: id) } }
        var resumption: BlobResumption?
        var last: any Error = LinkClientError.lost
        for attempt in 1...LinkClient.blobAttempts {
            let asking = Self.asking(command, from: resumption?.nextIndex ?? 0)
            do {
                // The resumption rides only with a command that actually asks for a tail, so a
                // thumbnail asked for again is asked for whole.
                return try await announced(
                    asking, resuming: asking == command ? nil : resumption)
            } catch let stopped as BlobInterrupted {
                last = stopped.reason
                resumption = stopped.resumption
                if let id = resumption?.budgetID { reservations.insert(id) }
                logger.notice(
                    """
                    A \(command.kind.rawValue, privacy: .public) stopped at chunk \
                    \(resumption?.nextIndex ?? 0, privacy: .public); asking for the rest.
                    """)
                guard attempt < LinkClient.blobAttempts else { break }
                try await Task.sleep(for: LinkBackoff.delay(after: attempt))
            } catch let error as LinkClientError where error.isWorthRepeating {
                // The reply itself never came, so no transfer opened and nothing was resumed
                // here; whatever an earlier attempt got to is still what the next one asks from.
                last = error
                logger.notice(
                    "A \(command.kind.rawValue, privacy: .public) went unanswered; asking again.")
                guard attempt < LinkClient.blobAttempts else { break }
                try await Task.sleep(for: LinkBackoff.delay(after: attempt))
            }
        }
        throw last
    }

    /// One attempt at one transfer: the reply that announces it, then the bytes it named.
    ///
    /// What it was resuming is filed under the request's own envelope id before the request goes
    /// out, because the reply's announcement is opened by `dispatch` — which knows the new blob's
    /// id and has to find the old blob's bytes at that same moment.
    private func announced(_ command: Command, resuming: BlobResumption?) async throws -> Data {
        let reply = try await ask(command) { [weak self] id in
            guard let resuming else { return }
            self?.resumptions[id] = resuming
        }
        switch reply {
        case .blob(let start):
            do { return try await blob(start.blobID) } catch {
                let kept = salvaged.removeValue(forKey: start.blobID)
                guard let again = error as? LinkClientError, again.isWorthRepeating else {
                    throw error
                }
                throw BlobInterrupted(reason: again, resumption: kept)
            }
        case .error(let error): throw error
        case .workflow, .multiHost, .ok, .queued, .entries: throw LinkClientError.unexpectedReply
        }
    }

    /// The same command, asking to carry on from `index` rather than to start again.
    ///
    /// Only a whole file resumes. A thumbnail is one chunk or two, so asking for the rest of one
    /// would be a round trip to save a round trip.
    private static func asking(_ command: Command, from index: UInt32) -> Command {
        guard case .fetchFile(let name, _) = command, index > 0 else { return command }
        return .fetchFile(name: name, fromChunk: index)
    }
}
