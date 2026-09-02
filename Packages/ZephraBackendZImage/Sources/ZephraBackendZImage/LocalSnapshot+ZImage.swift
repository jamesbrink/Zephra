import ZephraSnapshot

extension LocalSnapshot {
    /// What a Z-Image snapshot must contain to be loadable. Declared once, here, because this
    /// is the layer that knows the vendored loader's layout.
    static let zImage = LocalSnapshot(
        requiredEntries: ["model_index.json", "transformer", "text_encoder", "vae"]
    )
}
