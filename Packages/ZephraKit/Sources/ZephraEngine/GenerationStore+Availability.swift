import Foundation
import ZephraCore

/// Knowing what is on disk before anything is downloaded, so the interface can say "13.3 GB
/// download" beside a model rather than finding out by starting the transfer.
extension GenerationStore {
    /// Re-reads what is on disk for every model in the catalog, without downloading anything.
    ///
    /// The check runs on the inference actor, so it waits behind whatever that actor is already
    /// doing. Calling it while a load is under way is therefore slow, but never wrong.
    public func refreshAvailability() async {
        guard let inference = inferenceActor() else { return }
        var found: [ModelDescriptor.ID: ModelAvailability] = [:]
        for model in ModelCatalog.all {
            found[model.id] = await inference.availability(of: model)
        }
        availability = found
    }

    /// Steps off a chosen model that cannot be had at all — a local build that was deleted or
    /// never made — onto the first model this Mac can run and does have, so a launch lands on
    /// something that loads rather than on a failure naming a folder. A model that is merely
    /// not downloaded yet is kept: choosing it was the decision to download it.
    ///
    /// Returns whether the model changed. Read `availability` first; an unknown model is
    /// given the benefit of the doubt.
    @discardableResult
    public func fallBackIfUnobtainable(budget: MemoryBudget? = nil) -> Bool {
        guard availability[descriptor.id]?.isObtainable == false else { return false }
        let budget = budget ?? memoryBudget
        let candidates = ModelCatalog.fitting(budget: budget) + ModelCatalog.all
        guard let fallback = candidates.first(where: { availability[$0.id]?.isObtainable != false })
        else { return false }
        logger.notice(
            "\(self.descriptor.id, privacy: .public) is not on this Mac; using \(fallback.id, privacy: .public)"
        )
        adopt(fallback)
        return true
    }
}
