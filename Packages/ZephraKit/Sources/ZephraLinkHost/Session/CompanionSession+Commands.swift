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
        // A Mac whose GPU has stopped answering takes none of the eight commands that would
        // reach it (`needsTheGPU`): `enqueue`, `loadModel`, `unloadModel`, `switchModel`,
        // `upscale` and `animate`, and the two multi-host commands that put work on the
        // device — `offer` and `submit`. Each hears the Mac's own sentence rather than "cannot
        // load a model just now" or a plain `.refused`, which reads as a moment passing rather
        // than as a Mac that has to be relaunched. Seven of the eight are turned away here,
        // before the switch and before `remoteAdmission` — which answers an `enqueue` in the
        // same words anyway, and would otherwise be the only one of them that said anything
        // true. The eighth is the strict `submit`, which answers itself a few lines below,
        // once the receipt ledger has been read: it must not file a `.prepared` receipt for
        // work no device will ever run, and it must not refuse the repeat of a submit this Mac
        // did accept.
        if host.store.deviceLost, Self.needsTheGPU(command), !Self.isStrictSubmit(command) {
            throw LinkError(code: .refused, reason: EngineError.deviceLost.message)
        }
        switch command {
        case .multiHost(let command): return try performMultiHost(command, on: host)
        case .resync: return try resend(to: host, inReplyTo: id)
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
            let model = try Self.model(modelID)
            // `switchModel` is a no-op for a model this Mac cannot hold, and an `.ok` over a
            // no-op is a phone drawing a model the Mac never took. The phone is told, in the
            // words its own greyed row carries.
            if let refusal = Self.unholdable(model, on: host) { throw refusal }
            host.store.switchModel(to: model)
            return .ok
        case .loadModel(let modelID):
            // One meaning in both loading modes: make this the model and read it in now. Under
            // `.automatic` the switch already loads; under `.onDemand` the switch only adopts
            // and `loadModel()` does the work — a swap where another model's weights are in.
            let model = try Self.model(modelID)
            if let refusal = Self.unholdable(model, on: host) { throw refusal }
            // Answered `.ok` for a load that has already happened or is on its way, as
            // `unloadModel` is, because a request is repeated whenever its reply goes missing
            // and the repeat must not be told "cannot load" over its own first ask.
            if Self.isLoadedOrLoading(model, on: host.store) { return .ok }
            // Asked **before** the switch, not after. `loadModel()` returns silently when it
            // will not load — a model that is not on the disk, a Mac mid-run or mid-upscale, a
            // load already going — and switching first would then move the chosen model and
            // clamp the settings under the person at the keyboard while the phone was told the
            // load succeeded. That is the very thing this command exists to avoid.
            guard host.store.canLoad(model) else {
                throw LinkError(
                    code: .busy, reason: "This Mac cannot load a model just now.")
            }
            if model.id != host.store.descriptor.id { host.store.switchModel(to: model) }
            // Under `.automatic` the switch has already started the swap, and a second ask
            // would only log a refusal over it.
            if !host.store.isSwappingModel { host.store.loadModel() }
            return .ok
        case .unloadModel:
            // Answered `.ok` for an unload that has already happened or is happening, because
            // a request is repeated whenever its reply goes missing and a phone must not be
            // told "cannot unload" over the unload its own first ask performed.
            guard host.store.loadedDescriptor != nil, !host.store.isSwappingModel else {
                return .ok
            }
            guard host.store.canUnload else {
                throw LinkError(code: .busy, reason: "This Mac cannot unload a model just now.")
            }
            host.store.unloadModel()
            return .ok
        case .upscale(let name, let factor): return try upscale(name, factor: factor, on: host)
        case .animate(let name): return try animate(name, on: host)
        default: return try await performLibrary(command, id: id, on: host)
        }
    }

    /// Whether `model` is the chosen model and its weights are in, or on their way in.
    private static func isLoadedOrLoading(_ model: ModelDescriptor, on store: GenerationStore) -> Bool {
        guard model.id == store.descriptor.id else { return false }
        if store.isSwappingModel { return true }
        switch store.state {
        case .checkingModel, .downloading, .building, .loading, .warmingUp:
            return store.modelInUse?.id == model.id
        case .ready: return store.loadedDescriptor?.id == model.id
        default: return false
        }
    }

    /// The whole state again, for a phone that stepped over a hole in the stream.
    ///
    /// The `.ok` goes first and the snapshot behind it, in that order and on this one stream, so
    /// the phone's request closes before the state it asked for arrives. Nothing is remembered
    /// about it: a snapshot is the whole truth, and the deltas after it carry on as they were.
    private func resend(to host: CompanionHost, inReplyTo id: UUID) throws -> Reply? {
        host.logger.notice("companion is sending \(self.deviceName, privacy: .public) the world again")
        try reply(.ok, to: id)
        try send(
            StateSnapshotProjection.snapshot(
                store: host.store, index: host.index, hostName: host.hostName),
            kind: .snapshot)
        return nil
    }

    /// Queues a press of Generate on the phone's behalf.
    ///
    /// The reference picture is the blob the phone sent before the request; `GenerationRequest`
    /// strips the bytes on the way in and out, so this is the one place they are put back.
    ///
    /// A request whose id this session has already queued is answered with the run it made, not
    /// queued again: the phone asks a second time when the first `queued` reply went missing, and
    /// a hole in the stream must not cost somebody two generations.
    private func submit(_ request: GenerationRequest, to host: CompanionHost) throws -> Reply {
        if let already = runs[request.requestID] { return .queued(batchID: already) }
        let model = try Self.model(request.modelID)
        var settings = request.settings
        settings.referenceImages = try takeReferences(named: request.referenceBlobIDs, for: settings)
        let admission = host.store.remoteAdmission(
            for: model, settings: settings, count: request.count)
        if let refusal = Self.refusal(admission) { throw refusal }
        guard let batch = host.store.enqueue(settings, on: model, count: request.count) else {
            throw LinkError(code: .refused, reason: "This Mac did not take that request.")
        }
        remember(batch, for: request.requestID)
        return .queued(batchID: batch)
    }

    /// Keeps what one request id queued, oldest forgotten first.
    private func remember(_ batch: UUID, for requestID: UUID) {
        runs[requestID] = batch
        runOrder.append(requestID)
        while runOrder.count > Self.runMemory {
            runs.removeValue(forKey: runOrder.removeFirst())
        }
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
}
