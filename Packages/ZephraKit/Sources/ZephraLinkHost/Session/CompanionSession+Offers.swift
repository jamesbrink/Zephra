import Foundation
import ZephraCore
import ZephraEngine
import ZephraLinkProtocol

extension CompanionSession {
    func offer(_ strict: StrictGeneration, on host: CompanionHost) throws -> HostOffer {
        let request = strict.request
        let model = try Self.model(request.modelID)
        var settings = request.settings
        // Presence is enough for capabilities; actual bytes are authenticated before enqueue.
        // One stand-in per declared input rather than one for the lot, so the capability check
        // and `remoteAdmission` see the number of pictures this work would really read.
        guard strict.inputs.count <= ReferenceLimits.maximumPictures else {
            throw LinkError(
                code: .badRequest,
                reason: "A generation may read at most \(ReferenceLimits.maximumPictures) pictures.")
        }
        for input in strict.inputs {
            guard (1...16_777_216).contains(input.byteCount) else {
                throw LinkError(code: .badRequest, reason: "The reference is too large.")
            }
        }
        settings.referenceImages = strict.inputs.map { input in
            ReferencePicture(data: Data([0]), origin: nil, size: input.dimensions)
        }
        let store = host.store
        let loaded = store.loadedDescriptor?.id == model.id
        let key = store.timingKey(model: model, settings: settings)
        let estimate = key.flatMap { store.timings.estimate($0) }
        let execution = estimate.map { $0.execution * Double(request.count) }
        var waiting: Double? = 0
        let pending = (store.running.map { [$0] } ?? []) + store.queue
        var precedingModel = store.loadedDescriptor?.id
        for job in pending {
            var duration = store.remainingTiming(for: job)
            if precedingModel != job.model.id {
                let key = store.timingKey(model: job.model, settings: job.settings)
                let load = key.flatMap { store.timings.preparation(model: $0.modelID,
                    revision: $0.revision, residency: $0.residency) }
                let unload = precedingModel.map { store.timings.unload(model: $0) } ?? 0
                duration = duration.flatMap { run in load.flatMap { load in unload.map { run + load + $0 } } }
            }
            if let duration, let prior = waiting { waiting = prior + duration } else { waiting = nil }
            precedingModel = job.model.id
        }
        let unload = precedingModel.map { store.timings.unload(model: $0) } ?? 0
        let preparation = precedingModel == model.id ? 0 : key.flatMap {
            store.timings.preparation(model: $0.modelID, revision: $0.revision, residency: $0.residency)
        }.flatMap { load in unload.map { load + $0 } }
        let revision = pending.map { $0.id.uuidString }.joined(separator: ":")
        // `logging: false`: an offer is a paired phone's estimate, polled every few seconds
        // while nothing runs, and logging it at info would bury a real run's own admission line.
        return HostOffer(refusal: store.strictRefusal(
            for: model, settings: settings, count: request.count, logging: false),
            queueSeconds: waiting, preparationSeconds: preparation,
            executionSeconds: execution, memoryMargin: store.memoryBudget.bytes - store.strictMemory(for: model, settings: settings),
            modelLoaded: loaded, queueCount: pending.count, queueRevision: revision,
            physicalMemory: store.memoryBudget.physicalMemory,
            thermalState: ProcessInfo.processInfo.thermalState.rawValue,
            finalizationSeconds: estimate.map { $0.finalization * Double(request.count) },
            requiresInputTransfer: !strict.inputs.isEmpty, timingSampleCount: estimate?.samples)
    }
}
