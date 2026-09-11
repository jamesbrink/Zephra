import ZephraLinkProtocol

/// Which model the phone is drawing controls for.
///
/// The draft's, not the Mac's. Choosing a model sends a command and takes the new model's
/// schedule here in the same breath, and for the moment between the two the capsule must draw
/// the model somebody just chose rather than the one the Mac has not yet let go of. The Mac's
/// own is the fallback, for a draft naming a model this Mac no longer lists.
extension StateSnapshot {
    /// The summary of `modelID`, or the model in force where the snapshot does not list it.
    func model(named modelID: String) -> ModelSummary {
        models.first { $0.id == modelID } ?? model
    }
}
