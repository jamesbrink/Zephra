import ZephraLinkProtocol

/// What the Mac has in memory, said in a word beside a model's name.
///
/// The model *chosen* and the model *loaded* are two different facts now that a Mac can sit with
/// one chosen and nothing read in, and `EngineStateDTO` carries both: `modelID` is the choice and
/// `loadedModelID` is the weights. A phone that read them as one would draw a loaded row for a
/// model that is not there, which is the one thing this whole surface exists to stop.
///
/// Pure, and beside `ModelSummary+Choosing` rather than inside the picker, for that file's
/// reason: the words and the fact are one answer, and a view that worked it out for itself could
/// disagree with the Mac about what is loaded.
///
/// A Mac too old to stamp `loadedModelID` is not a special case here. Its decoder supplies the
/// honest reading of what that Mac meant — nothing loaded while it was idle, the chosen model in
/// play otherwise — so the same two answers are drawn over either Mac.
enum ModelLoadWord {
    /// The secondary word on one row of a list of models: "Loaded" for the weights in memory,
    /// nil for every other row and for a Mac that has said nothing yet.
    static func marker(for modelID: String, engine: EngineStateDTO?) -> String? {
        guard let engine, engine.loadedModelID == modelID else { return nil }
        return "Loaded"
    }

    /// A model named with what the Mac has done about it: "klein 4-bit" when its weights are the
    /// ones in memory, "klein 4-bit \u{00B7} Not loaded" when nothing is.
    ///
    /// Silent about a *different* model being loaded: that is the Mac's business and not this
    /// name's, and the row for the model that is loaded already says so.
    static func label(_ name: String, modelID: String, engine: EngineStateDTO?) -> String {
        guard let engine else { return name }
        if engine.loadedModelID == nil { return "\(name) \u{00B7} Not loaded" }
        return name
    }
}
