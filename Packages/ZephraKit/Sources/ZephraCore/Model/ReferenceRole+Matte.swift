/// What is said about a transparent picture handed to a model that does not read transparency.
///
/// Every reference path but one draws the picture into an opaque bitmap before it encodes it, so
/// a cut-out arrives at the model over white — `ModelCapabilities.readsTransparentReferences` is
/// what says which. The sentence is the same whatever the picture is *for*, so it sits on the
/// role beside every other string the interface says about a reference rather than in a view:
/// one wording, spelled once, and tested.
extension ReferenceRole {
    /// One line under the well, naming the model doing the reading, or nothing to say at all
    /// when the model reads the transparency itself.
    ///
    /// The model is named because the answer moves with it: the same cut-out is read over white
    /// by one model and kept by the next, and a note that said only "read over white" would look
    /// like a fact about the picture instead of a fact about the pairing.
    public func whiteMatteNote(modelName: String) -> String {
        "Read over white by \(modelName)."
    }
}
