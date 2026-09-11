/// Which model turns a picture into a clip, if this build ships one at all.
extension ModelCatalog {
    /// The model a picture would be animated with: the first entry that makes clips and reads
    /// a picture, or nil when this build ships none.
    ///
    /// A capability question rather than a family one, so nothing above the catalog has to name
    /// LTX-2.5 to know whether "Animate" is worth offering — and a second video family, or a
    /// build with the video family left out, changes the answer here and nowhere else.
    /// `models` is a parameter only so the rule can be tested against lists this build has not
    /// got; every caller takes the catalog.
    public static func animator(among models: [ModelDescriptor] = all) -> ModelDescriptor? {
        models.first { $0.capabilities.producesVideo && $0.capabilities.supportsReferenceImage }
    }

    /// The model a clip made by `modelID` would be carried on with: the clip's own model when
    /// it can hold a clip's end, or else whichever model animates a picture, which continues
    /// from the last frame alone. Nil when nothing in `models` makes clips from a picture.
    public static func continuer(
        for modelID: String, among models: [ModelDescriptor] = all
    ) -> ModelDescriptor? {
        if let own = models.first(where: { $0.id == modelID }), own.capabilities.supportsContinuation {
            return own
        }
        return animator(among: models)
    }
}
