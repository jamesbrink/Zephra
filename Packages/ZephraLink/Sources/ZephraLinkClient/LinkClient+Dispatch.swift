import Foundation
import ZephraLinkProtocol

/// What one opened frame means, which is the whole of the session loop.
extension LinkClient {
    /// One frame, sorted by what it is.
    func dispatch(_ frame: Frame) {
        switch frame {
        case .envelope(let envelope): dispatch(envelope)
        case .chunk(let chunk): receive(chunk)
        }
    }

    /// One message.
    ///
    /// A body that will not decode is dropped with a log line rather than taken as a reason to
    /// close: the envelope arrived sealed and in order, so it is this build not knowing a shape
    /// a newer Mac sent, which is the case the envelope's opaque body exists for.
    private func dispatch(_ envelope: Envelope) {
        switch envelope.kind {
        case .snapshot:
            snapshot = decode(StateSnapshot.self, from: envelope)
            // Every connect brings one, and it is the frame that says the session is up: the
            // library the Mac holds is read across from here, since nothing else will send it.
            startLibraryPull()
        case .delta:
            guard let delta = decode(StateDelta.self, from: envelope) else { return }
            snapshot = snapshot?.applying(delta)
            apply(delta)
        case .preview:
            preview = decode(PreviewFrameDTO.self, from: envelope)
        case .reply:
            guard let id = envelope.inReplyTo, let reply = decode(Reply.self, from: envelope)
            else { return }
            // The announcement is opened before the request that asked for it is resumed: the
            // chunks behind it are the next frames on this same stream.
            if case .blob(let start) = reply { announce(start) }
            answer(id, with: reply)
        case .blobStart:
            guard let start = decode(BlobStart.self, from: envelope) else { return }
            announce(start)
        case .error:
            guard let error = decode(LinkError.self, from: envelope) else { return }
            received(error, inReplyTo: envelope.inReplyTo)
        case .ping:
            try? send(.envelope(Envelope(kind: .pong, body: Data("{}".utf8))))
        case .pong:
            break
        case .hello, .accept, .confirm, .request:
            logger.notice(
                "A \(envelope.kind.rawValue, privacy: .public) arrived from the Mac and was dropped."
            )
        }
    }

    /// What a delta changes beyond the snapshot it edits.
    ///
    /// The library list is the client's, not the snapshot's: the snapshot counts the folder and
    /// the phone holds the window it has been sent. The preview goes when the engine stops
    /// being busy, which is every way a run ends.
    private func apply(_ delta: StateDelta) {
        switch delta {
        case .library(let change): apply(change)
        case .engine(let engine) where !engine.isBusy: preview = nil
        default: break
        }
    }

    /// One change to the library the phone is holding.
    private func apply(_ change: LibraryChange) {
        switch change {
        case .reset(let entries, _):
            library = entries
        case .upserted(let entries):
            for entry in entries {
                if let index = library.firstIndex(where: { $0.fileName == entry.fileName }) {
                    library[index] = entry
                } else {
                    library.insert(entry, at: 0)
                }
            }
        case .removed(let names):
            let gone = Set(names)
            library.removeAll { gone.contains($0.fileName) }
        }
    }

    /// A refusal that came on its own, rather than as a reply.
    ///
    /// `revoked` is the one that changes anything here: the Mac has withdrawn the pairing, so
    /// the keys this phone holds are worth nothing and keeping them would only make every later
    /// connection fail in a way nobody could read.
    private func received(_ error: LinkError, inReplyTo id: UUID?) {
        if let id { answer(id, with: .error(error)) }
        guard error.code == .revoked else { return }
        logger.notice("The Mac withdrew this pairing.")
        Task { await self.forgetHost() }
    }

    /// A body read back, or nil with a line in the log.
    private func decode<T: Decodable>(_ type: T.Type, from envelope: Envelope) -> T? {
        do {
            return try envelope.decode(type)
        } catch {
            logger.error("A \(envelope.kind.rawValue, privacy: .public) body did not decode.")
            return nil
        }
    }
}
