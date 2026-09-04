import ZephraSnapshot

extension LocalSnapshot {
    /// What a Qwen-Image snapshot must contain to be loadable.
    static let qwenImage = LocalSnapshot(
        requiredEntries: [
            "model_index.json", "quantization.json", "transformer", "text_encoder", "vae",
            "tokenizer", "scheduler",
        ]
    )

    /// What the bf16 release must hold before the packer is pointed at it: the two components
    /// it packs, each with the index that says how many shards it is in, and the three it
    /// copies across whole. Paired with `HubSnapshotCheck.isComplete`, which holds the
    /// directory to every shard those indexes name — the transformer alone is nine of them, so
    /// a download stopped between two must not read as a release.
    ///
    /// The tokenizer is named by `tokenizer_config.json` and `vocab.json` rather than by a
    /// `tokenizer.json`, which this repository does not ship.
    static let qwenImageRelease = LocalSnapshot(
        requiredEntries: [
            "model_index.json",
            "transformer/config.json",
            "transformer/diffusion_pytorch_model.safetensors.index.json",
            "text_encoder/config.json", "text_encoder/model.safetensors.index.json",
            "vae/config.json", "vae/diffusion_pytorch_model.safetensors",
            "tokenizer/tokenizer_config.json", "tokenizer/vocab.json",
            "scheduler/scheduler_config.json",
        ]
    )
}
