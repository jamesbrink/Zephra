import ZephraSnapshot

extension LocalSnapshot {
    /// What a packed Wan 2.2 directory must hold before it counts as built.
    ///
    /// `quantization.json` is listed first on purpose: the packer writes it last, after every
    /// component, so a build stopped or crashed half-way reads as incomplete and is redone
    /// rather than half-loaded. The tokenizer is a directory of its own, copied whole, as the
    /// release keeps it.
    static let wan = LocalSnapshot(requiredEntries: [
        "quantization.json", "transformer", "text_encoder", "vae",
        "tokenizer/tokenizer.json", "text_encoder/config.json", "transformer/config.json",
        "vae/config.json",
    ])

    /// What the `FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers` release must hold before the
    /// packer is pointed at it: the exact files the plan reads, so a download stopped between
    /// files is a download, not a failed build. The scheduler's config and the README are
    /// fetched for what they say and not required.
    static let wanRelease = LocalSnapshot(requiredEntries: [
        "model_index.json",
        "transformer/config.json", "transformer/diffusion_pytorch_model.safetensors",
        "vae/config.json", "vae/diffusion_pytorch_model.safetensors",
        "text_encoder/config.json", "text_encoder/model.safetensors.index.json",
        "text_encoder/model-00001-of-00003.safetensors",
        "text_encoder/model-00002-of-00003.safetensors",
        "text_encoder/model-00003-of-00003.safetensors",
        "tokenizer/tokenizer.json", "tokenizer/tokenizer_config.json",
    ])
}
