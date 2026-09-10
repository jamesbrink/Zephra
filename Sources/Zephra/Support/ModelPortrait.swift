import ZephraCore

/// How a model introduces itself in the first-launch chooser: a picture it made, and one line
/// saying what it is for.
///
/// Presentation rather than a catalog fact, so it lives here beside `ReferenceRole` rather than
/// on `ModelDescriptor` — the numbers in a catalog entry are measured, and these are written.
/// One place for both halves, so adding a model is one entry here plus one image set;
/// `ModelPortraitTests` walks `ModelCatalog.all` and fails when a model has neither.
struct ModelPortrait: Hashable {
    /// One line on what this model is for. Sentence case, since it reads as a caption.
    let summary: String

    /// The image set in `Assets.xcassets` holding a picture this model made. Every sample is
    /// the same prompt at the same seed, so the cards compare models and not prompts; see
    /// `scripts/make-samples.sh`.
    let sampleName: String

    /// The portrait for a model, or nil for one the app has no copy written for — a catalog
    /// entry added without one, which the chooser draws as a plain card rather than refusing
    /// to list.
    static func of(_ model: ModelDescriptor) -> ModelPortrait? {
        guard let summary = summaries[model.id] else { return nil }
        return ModelPortrait(summary: summary, sampleName: "Sample-\(model.id)")
    }

    /// The written half, by catalog identifier.
    private static let summaries: [ModelDescriptor.ID: String] = [
        "flux2-klein-4b-4bit":
            "The quickest way in: four steps, fine detail, and the smallest download here.",
        "flux2-klein-4b-8bit":
            "klein again with more of its precision kept, for a Mac with the memory to hold it.",
        "z-image-turbo-8bit":
            "Nine steps and a painterly hand. The most faithful of the two Z-Image builds.",
        "z-image-turbo-4bit":
            "Z-Image packed small enough for a 16 GB Mac, for a little of its detail.",
        "qwen-image-2512-4bit":
            "Renders legible text and dense scenes. The largest picture model Zephra runs.",
        "wan-2.2-ti2v-5b-4bit":
            "The quick clip maker: three steps, from a prompt or from a picture it holds as the first frame.",
        "ltx-2.5-distilled-4bit":
            "Makes short clips rather than pictures, up to five seconds at 24 frames a second.",
    ]
}
