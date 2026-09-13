import Foundation
import ZephraCore

/// Knowing what is on disk before anything is downloaded, so the interface can say "13.3 GB
/// download" beside a model rather than finding out by starting the transfer.
extension GenerationStore {
    /// Reads what is on disk for every model and steps off one that cannot be had, without
    /// loading anything: the half of `bootstrap` a picker needs before a model has been
    /// chosen, so a first launch can say what each model costs without fetching one.
    public func surveyAvailability() async {
        await refreshAvailability()
        fallBackIfUnrunnable()
    }

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

    /// Steps off a chosen model this Mac cannot run — one that cannot be had, a local build
    /// that was deleted or never made, or one this Mac has not the memory to hold — onto the
    /// first model it can run and does have, so a launch lands on something that loads rather
    /// than on a failure naming a folder or a figure. A model that is merely not downloaded
    /// yet is kept: choosing it was the decision to download it.
    ///
    /// The candidates are what this Mac may choose from, and nothing else: a Mac that can hold
    /// none of them keeps what it had and is told why by the guard, since stepping it onto
    /// another model it also cannot hold helps nobody.
    ///
    /// Returns whether the model changed. Read `availability` first; an unknown model is
    /// given the benefit of the doubt.
    @discardableResult
    public func fallBackIfUnrunnable(budget: MemoryBudget? = nil) -> Bool {
        let budget = budget ?? memoryBudget
        let unobtainable = availability[descriptor.id]?.isObtainable == false
        let unholdable = !ModelCatalog.fit(descriptor, budget: budget).isSelectable
        guard unobtainable || unholdable else { return false }
        let candidates = ModelCatalog.fitting(budget: budget)
        guard let fallback = candidates.first(where: { availability[$0.id]?.isObtainable != false })
        else { return false }
        logger.notice(
            "\(self.descriptor.id, privacy: .public) cannot be run on this Mac; using \(fallback.id, privacy: .public)"
        )
        adopt(fallback)
        return true
    }
}
