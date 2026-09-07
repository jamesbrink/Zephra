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
}
