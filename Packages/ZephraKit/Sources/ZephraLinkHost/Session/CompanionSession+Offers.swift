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
        if let input = strict.input {
            guard (1...16_777_216).contains(input.byteCount) else {
                throw LinkError(code: .badRequest, reason: "The reference is too large.")
            }
            settings.referenceImage = Data([0])
        }
        let store = host.store
        let loaded = store.loadedDescriptor?.id == model.id
        let records = host.index.items.compactMap(\.provenance.record).suffix(64)
        func duration(_ modelID: String, _ settings: GenerationSettings) -> Double? {
            let values = records.filter {
                $0.modelID == modelID && $0.width == settings.size.width && $0.height == settings.size.height
                    && $0.steps == settings.steps && ($0.frameCount ?? 1) == settings.frames
                    && $0.durationSeconds.isFinite && $0.durationSeconds > 0
            }.map(\.durationSeconds)
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count) * 1.2
        }
        let execution = duration(model.id, settings).map { $0 * Double(request.count) }
        var waiting: Double? = 0
        let pending = store.queue + (store.running.map { [$0] } ?? [])
        for job in pending {
            if let elapsed = duration(job.model.id, job.settings), let prior = waiting {
                waiting = prior + elapsed
            } else { waiting = nil }
        }
        let revision = pending.map { $0.id.uuidString }.joined(separator: ":")
        return HostOffer(refusal: store.strictRefusal(for: model, settings: settings, count: request.count),
            queueSeconds: waiting, preparationSeconds: loaded ? 0 : nil,
            executionSeconds: execution, memoryMargin: store.memoryBudget.bytes - store.strictMemory(for: model, settings: settings),
            modelLoaded: loaded, queueCount: pending.count, queueRevision: revision,
            physicalMemory: store.memoryBudget.physicalMemory,
            thermalState: ProcessInfo.processInfo.thermalState.rawValue)
    }
}
