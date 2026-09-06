import ZephraSnapshot

extension LocalSnapshot {
    /// What a packed LTX-2.5 directory must hold before it counts as built.
    ///
    /// `quantization.json` is listed first on purpose: the packer writes it last, after every
    /// component, so a build stopped or crashed half-way reads as incomplete and is redone
    /// rather than half-loaded.
    static let ltx2 = LocalSnapshot(requiredEntries: [
        "quantization.json", "transformer", "connector", "text_encoder", "vae",
        "text_encoder/tokenizer.json", "text_encoder/config.json", "config.json",
    ])

    /// What the `mlx-community/ltx-2.5-mlx` release must hold before the packer is pointed at
    /// it: the exact files the plan reads, so a download stopped between files is a download,
    /// not a failed build. The audio autoencoder, the vocoder, the upscalers, the dev
    /// transformer and the video encoder are not fetched and not required.
    static let ltx2Release = LocalSnapshot(requiredEntries: [
        "config.json", "embedded_config.json", "LICENSE.md",
        "transformer-distilled.safetensors", "connector.safetensors", "vae_decoder.safetensors",
        "gemma4-12b-ltx-v1/config.json", "gemma4-12b-ltx-v1/model.safetensors",
        "gemma4-12b-ltx-v1/tokenizer.json", "gemma4-12b-ltx-v1/tokenizer_config.json",
    ])
}
