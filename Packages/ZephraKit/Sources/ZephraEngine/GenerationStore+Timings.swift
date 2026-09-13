import Foundation
import ZephraCore

extension GenerationStore {
    /// A pinned download or hub snapshot has a resolved revision. Unstamped local weights
    /// deliberately use a fresh load identity, so two unknown builds never share timings.
    func timingRevision(at directory: URL) -> String? {
        if let value = try? String(contentsOf: directory.appending(path: ".zephra-commit"), encoding: .utf8),
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        let name = directory.lastPathComponent
        return name.count == 40 && name.allSatisfy(\.isHexDigit) ? name : nil
    }
    public func timingKey(model: ModelDescriptor, settings: GenerationSettings) -> WorkloadTimingKey? {
        guard let revision = timingRevisions[model.id] else { return nil }
        let loaded = loadedDescriptor?.id == model.id
        if !loaded {
            guard let directory = timingDirectories[model.id], timingRevision(at: directory) == revision else { return nil }
        }
        return WorkloadTimingKey(modelID: model.id, revision: revision,
            residency: loaded ? loadedResidency ?? weightResidencyPolicy.residency(for: model)
                : weightResidencyPolicy.residency(for: model),
            settings: settings, tiled: vaeTile(for: model) != nil)
    }
    func timingKey(for job: QueuedGeneration) -> WorkloadTimingKey? {
        if let chain = job.chain, let key = chains[chain.chainID]?.timingKey { return key }
        var settings = job.settings
        if let chain = job.chain, let progress = chains[chain.chainID] {
            settings.frames = ChainPlan.joinedFrames(progress.segments,
                context: job.model.capabilities.defaultContinuationFrames)
        }
        return timingKey(model: job.model, settings: settings)
    }
    /// Includes every remaining pass of a chain; subtracts only time actually spent running.
    public func remainingTiming(for job: QueuedGeneration) -> Double? {
        guard let key = timingKey(for: job), let estimate = timings.estimate(key) else { return nil }
        var elapsed = job.chain.flatMap { chains[$0.chainID]?.elapsed.seconds } ?? 0
        if running?.id == job.id, let started = timingRunStarted { elapsed += (ContinuousClock.now - started).seconds }
        // Past the estimate is uncertainty, not evidence that a busy GPU has finished.
        return max((estimate.execution + estimate.finalization) * 0.1,
                   estimate.execution + estimate.finalization - elapsed)
    }
}
