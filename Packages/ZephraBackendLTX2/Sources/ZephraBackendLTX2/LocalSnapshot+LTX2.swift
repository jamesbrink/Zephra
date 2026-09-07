import ZephraSnapshot

extension LocalSnapshot {
    /// What a packed LTX-2.5 directory must hold before it counts as built.
    ///
    /// `quantization.json` is listed first on purpose: the packer writes it last, after every
    /// component, so a build stopped or crashed half-way reads as incomplete and is redone
    /// rather than half-loaded.
    ///
    /// Nothing here names the video encoder, though the `vae` component now carries it: the
    /// packer writes its components as `model*.safetensors` and never under the source file's
    /// name, so a rule naming it would read every fresh build as unbuilt. A variant packed
    /// before the encoder was fetched is caught where it should be, by
    /// `PackedProvenance.identity`, which carries the descriptor's file patterns.
    static let ltx2 = LocalSnapshot(requiredEntries: [
        "quantization.json", "transformer", "connector", "text_encoder", "vae",
        "text_encoder/tokenizer.json", "text_encoder/config.json", "config.json",
    ])

    /// What the `mlx-community/ltx-2.5-mlx` release must hold before the packer is pointed at
    /// it: the exact files the plan reads, so a download stopped between files is a download,
    /// not a failed build. The audio autoencoder, the vocoder, the upscalers and the dev
    /// transformer are not fetched and not required. The video encoder is: a first frame is
    /// held by encoding the picture, and a pack fetched before that could be done has every
    /// other file and not this one, which must read as a download to finish.
    static let ltx2Release = LocalSnapshot(requiredEntries: [
        "config.json", "embedded_config.json", "LICENSE.md",
        "transformer-distilled.safetensors", "connector.safetensors", "vae_decoder.safetensors",
        "vae_encoder.safetensors",
        "gemma4-12b-ltx-v1/config.json", "gemma4-12b-ltx-v1/model.safetensors",
        "gemma4-12b-ltx-v1/tokenizer.json", "gemma4-12b-ltx-v1/tokenizer_config.json",
    ])
}
