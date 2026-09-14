import Foundation
import ZephraCore

extension GenerationStore {
    /// Checks the exact workload without loading weights or acquiring storage.
    public func strictRefusal(for model: ModelDescriptor, settings: GenerationSettings,
                              count: Int, admitting: Bool = true) -> String? {
        if admitting, case .admitted = remoteAdmission(for: model, settings: settings, count: count) {} else if admitting {
            return remoteAdmission(for: model, settings: settings, count: count).reason
        }
        guard availability[model.id] == .available else { return "This model is not ready on this Mac." }
        guard !admitting || settings.continuation == nil else { return "Clip continuation is not supported over the link." }
        var normalized = model.capabilities.clamp(settings)
        normalized.frames = ChainPlan.frames(settings.frames, capabilities: model.capabilities)
        guard normalized == settings else { return "This Mac cannot run these exact settings." }
        guard strictMemory(for: model, settings: settings) <= memoryBudget.bytes else {
            return "This job's estimated peak exceeds this Mac's GPU memory budget."
        }
        guard ProcessInfo.processInfo.thermalState != .critical else { return "This Mac needs to cool down." }
        return nil
    }

    /// Conservative scaling of the catalog's measured peak; never a total-RAM fit claim.
    public func strictMemory(for model: ModelDescriptor, settings: GenerationSettings) -> Double {
        let pixels = Double(settings.size.width) * Double(settings.size.height)
        let baseline = Double(model.capabilities.defaultSize.width) * Double(model.capabilities.defaultSize.height)
        let frames = Double(min(settings.frames, model.capabilities.frameBounds.upperBound))
        let scale = max(1, pixels / max(1, baseline)) * max(1, frames / Double(max(1, model.capabilities.defaultFrames)))
        let planned = weightResidencyPolicy.residency(for: model)
        let residency = loadedDescriptor?.id == model.id ? loadedResidency ?? planned : planned
        let peak = memoryGuard.peakBytes(of: model, residency: residency, tile: vaeTile(for: model))
        return Double(peak) * scale
    }

    /// Cancels only the run still named by the UI, preserving unrelated queued work.
    public func cancelRun(_ id: UUID) {
        guard let current = running, current.id == id || current.batchID == id else { return }
        let retained = queue.filter { $0.batchID != current.batchID }
        let retainedChains = chains
        cancel()
        chains = retainedChains
        if let chain = current.chain { chains[chain.chainID] = nil }
        queue = retained
    }
}
