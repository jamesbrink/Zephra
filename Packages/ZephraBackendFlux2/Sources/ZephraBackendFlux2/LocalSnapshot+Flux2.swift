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

    /// What the klein release must hold before the packer is pointed at it: the exact files
    /// the plan reads, so a download stopped between files is a download, not a failed build.
    static let flux2Release = LocalSnapshot(requiredEntries: [
        "model_index.json",
        "transformer/config.json", "transformer/diffusion_pytorch_model.safetensors",
        "text_encoder/config.json", "text_encoder/model.safetensors.index.json",
        "text_encoder/model-00001-of-00002.safetensors",
        "text_encoder/model-00002-of-00002.safetensors",
        "vae/config.json", "vae/diffusion_pytorch_model.safetensors",
        "tokenizer/tokenizer.json", "tokenizer/tokenizer_config.json",
        "scheduler/scheduler_config.json",
    ])
}
