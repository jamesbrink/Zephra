import ZephraSnapshot

extension LocalSnapshot {
    /// What a Qwen-Image snapshot must contain to be loadable.
    static let qwenImage = LocalSnapshot(
        requiredEntries: [
            "model_index.json", "quantization.json", "transformer", "text_encoder", "vae",
            "tokenizer", "scheduler",
        ]
    )
}
