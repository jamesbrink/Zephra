import ZephraSnapshot

extension LocalSnapshot {
    /// What a packed klein directory must hold before it counts as built.
    ///
    /// `quantization.json` is listed first on purpose: the packer writes it last, after every
    /// component, so a build stopped or crashed half-way reads as incomplete and is redone
    /// rather than half-loaded.
    static let flux2 = LocalSnapshot(requiredEntries: [
        "quantization.json", "transformer", "text_encoder", "vae", "tokenizer", "scheduler",
    ])
}
