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
}
