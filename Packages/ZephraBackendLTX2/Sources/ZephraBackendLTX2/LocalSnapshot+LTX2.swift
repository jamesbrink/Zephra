import ZephraCore
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
    ///
    /// `upsampler` is the spatial latent upscaler the second stage reads; a variant packed
    /// before it was part of the build has every other directory and not this one, and reads
    /// as unbuilt so the second stage never finds it missing mid-clip.
    static let ltx2 = LocalSnapshot(requiredEntries: ltx2Entries)

    /// The same with the audio lane's two components, which the audio variant loads too.
    static let ltx2Audio = LocalSnapshot(requiredEntries: ltx2Entries + ["audio_vae", "vocoder"])

    private static let ltx2Entries = [
        "quantization.json", "transformer", "connector", "text_encoder", "vae", "upsampler",
        "text_encoder/tokenizer.json", "text_encoder/config.json", "config.json",
        "spatial_upscaler_x2_v1_1_config.json",
    ]

    /// The variant `descriptor` loads: with the audio components when it makes sound.
    static func ltx2(for descriptor: ModelDescriptor) -> LocalSnapshot {
        descriptor.capabilities.producesAudio ? ltx2Audio : ltx2
    }

    /// The release `descriptor` builds from: the audio files required too when it makes sound.
    static func ltx2Release(for descriptor: ModelDescriptor) -> LocalSnapshot {
        descriptor.capabilities.producesAudio ? ltx2AudioRelease : ltx2Release
    }

    /// What the `mlx-community/ltx-2.5-mlx` release must hold before the packer is pointed at
    /// it: the exact files the plan reads, so a download stopped between files is a download,
    /// not a failed build. The audio autoencoder, the vocoder, the temporal upscaler and the
    /// dev transformer are not fetched and not required. The video encoder and the spatial
    /// upscaler are: a first frame is held by encoding the picture and the second stage
    /// doubles the latent, and a pack fetched before either could be done has every other
    /// file and not these, which must read as a download to finish.
    static let ltx2Release = LocalSnapshot(requiredEntries: ltx2ReleaseEntries)

    /// The release with the audio autoencoder and the vocoder beside it.
    static let ltx2AudioRelease = LocalSnapshot(
        requiredEntries: ltx2ReleaseEntries + ["audio_vae.safetensors", "vocoder.safetensors"])

    private static let ltx2ReleaseEntries = [
        "config.json", "embedded_config.json", "LICENSE.md",
        "transformer-distilled.safetensors", "connector.safetensors", "vae_decoder.safetensors",
        "vae_encoder.safetensors", "spatial_upscaler_x2_v1_1.safetensors",
        "spatial_upscaler_x2_v1_1_config.json",
        "gemma4-12b-ltx-v1/config.json", "gemma4-12b-ltx-v1/model.safetensors",
        "gemma4-12b-ltx-v1/tokenizer.json", "gemma4-12b-ltx-v1/tokenizer_config.json",
    ]
}
