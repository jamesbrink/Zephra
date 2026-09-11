import Foundation
import ZephraCore
import ZephraEngine
import ZephraLinkProtocol

/// What a phone may ask for, and what each ask turns into on the Mac.
///
/// Every command gets exactly one reply, a refusal included, so a phone can hold a request open
/// and know it will close. Nothing here writes `settings` or `descriptor`, sets `index.query`, or
/// calls `generate(count:)`: the person at the Mac may be halfway through typing a prompt, and a
/// remote submit that moved the capsule would be a bug nobody could explain.
extension CompanionSession {
    /// Runs one command and answers it.
    func handle(_ command: Command, id: UUID) async {
        do {
            if let answer = try await perform(command, id: id) {
                try reply(answer, to: id)
            }
        } catch let error as LinkError {
            try? reply(.error(error), to: id)
        } catch {
            try? reply(
                .error(LinkError(code: .badRequest, reason: error.localizedDescription)), to: id)
        }
    }

    /// The answer to one command, or nil when the command answered itself — a blob, whose
    /// announcement is its reply and whose chunks follow it.
    private func perform(_ command: Command, id: UUID) async throws -> Reply? {
        guard let host else { throw LinkError.refused }
        switch command {
        case .enqueue(let request): return try submit(request, to: host)
        case .cancel:
            host.store.cancel()
            return .ok
        case .removeFromQueue(let entry):
            host.store.removeFromQueue(entry)
            return .ok
        case .clearQueue:
            host.store.clearQueue()
            return .ok
        case .switchModel(let modelID):
            host.store.switchModel(to: try Self.model(modelID))
            return .ok
        case .upscale(let name, let factor): return try upscale(name, factor: factor, on: host)
        case .animate(let name): return try animate(name, on: host)
        default: return try await performLibrary(command, id: id, on: host)
        }
    }

    /// Queues a press of Generate on the phone's behalf.
    ///
    /// The reference picture is the blob the phone sent before the request; `GenerationRequest`
    /// strips the bytes on the way in and out, so this is the one place they are put back.
    private func submit(_ request: GenerationRequest, to host: CompanionHost) throws -> Reply {
        let model = try Self.model(request.modelID)
        var settings = request.settings
        if let blobID = request.referenceBlobID {
            guard let picture = blobs[blobID] else {
                throw LinkError(
                    code: .notFound, reason: "The picture for that request never arrived.")
            }
            settings.referenceImage = picture
            blobs.removeValue(forKey: blobID)
        }
        let admission = host.store.remoteAdmission(
            for: model, settings: settings, count: request.count)
        if let refusal = Self.refusal(admission) { throw refusal }
        guard let batch = host.store.enqueue(settings, on: model, count: request.count) else {
            throw LinkError(code: .refused, reason: "This Mac did not take that request.")
        }
        return .queued(batchID: batch)
    }

    /// Makes one picture larger. Pictures only: `LibraryItem.exportURL` is a clip for a clip, and
    /// the upscaler takes PNG bytes.
    private func upscale(_ name: String, factor: Int, on host: CompanionHost) throws -> Reply {
        guard factor == 2 || factor == 4 else {
            throw LinkError(code: .badRequest, reason: "Zephra upscales by 2x or 4x.")
        }
        let item = try item(named: name)
        guard !item.isVideo else {
            throw LinkError(code: .unsupported, reason: "A clip cannot be made larger.")
        }
        guard host.store.canUpscale else {
            throw LinkError(code: .busy, reason: "This Mac cannot upscale a picture just now.")
        }
        host.store.upscale(.file(item.url), factor: factor)
        return .ok
    }

    /// Sets the next generation up to animate one picture, exactly as Animate does on the Mac.
    private func animate(_ name: String, on host: CompanionHost) throws -> Reply {
        guard host.store.clips != nil else {
            throw LinkError(code: .unsupported, reason: "This copy of Zephra cannot make clips.")
        }
        guard host.store.canAnimate else {
            throw LinkError(code: .busy, reason: "This Mac cannot start a clip just now.")
        }
        let item = try item(named: name)
        let url = item.url
        host.store.animate(origin: item.fileName) { try? Data(contentsOf: url) }
        return .ok
    }

    /// The catalog entry a command names, or a refusal the phone can show.
    static func model(_ id: String) throws -> ModelDescriptor {
        guard let model = ModelCatalog.descriptor(id: id) else {
            throw LinkError(
                code: .notFound, reason: "This Mac's Zephra does not know a model called \(id).")
        }
        return model
    }

    /// One admission answer as the refusal it is, or nil when the request was admitted.
    ///
    /// The three ways a request can fail are three different words on a phone, and the
    /// distinction is also what says whether asking again in a moment is worth anything.
    static func refusal(_ admission: RemoteAdmission) -> LinkError? {
        switch admission {
        case .admitted: nil
        case .busy(let reason): LinkError(code: .busy, reason: reason)
        case .refused(let reason): LinkError(code: .refused, reason: reason)
        case .badRequest(let reason): LinkError(code: .badRequest, reason: reason)
        }
    }
}
