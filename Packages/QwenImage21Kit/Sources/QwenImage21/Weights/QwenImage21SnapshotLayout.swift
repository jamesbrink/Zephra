import Foundation

/// What a Qwen-Image 2.1 directory holds, for the two questions a host asks before it loads
/// one: is this download finished, and is this packed variant complete.
///
/// The names live here rather than in the backend because they are facts about the release and
/// about what `QwenImage21Pipeline.loadModel(at:...)` reads, and those two are one thing. The
/// backend turns them into `ZephraSnapshot.LocalSnapshot` entries; this package cannot import
/// that and does not need to.
public enum QwenImage21SnapshotLayout {
    /// The five directories a snapshot is read out of, packed or not.
    ///
    /// `processor` carries the tokenizer as well as `preprocessor_config.json`: 2.1 publishes
    /// the fast tokenizer there rather than in a `tokenizer/` of its own, so there is no sixth
    /// directory and a variant that packed one would be a variant this port cannot read.
    public static let directories = QwenImage21Configuration.Component.allCases.map(\.directoryName)

    /// What a packed variant must hold before it counts as built.
    ///
    /// `quantization.json` is listed **first** on purpose: the packer writes it last, after
    /// every component, so a build stopped or crashed part-way reads as incomplete and is
    /// redone rather than half-loaded.
    public static let builtEntries: [String] = ["quantization.json"] + directories

    /// What the release must hold before the packer is pointed at it: the exact files the load
    /// and the plan read, so a download stopped between shards is a download and not a failed
    /// build.
    ///
    /// `model_index.json` is listed because the release ships one and it is what tells a 2.1
    /// snapshot from a Qwen-Image 2512 one before a weight is read — the two have the same five
    /// directories with the same file names inside them. It is 447 bytes.
    /// `QwenImage21Configuration.modelIndex(in:)` still answers nil rather than throwing when
    /// it is absent, because a **packed variant** is built from the component directories alone
    /// and carries none; a file that is there and names another pipeline throws.
    public static let releaseEntries: [String] =
        [
            "model_index.json",
            "transformer/config.json",
            "transformer/diffusion_pytorch_model.safetensors.index.json",
            "transformer/diffusion_pytorch_model-00001-of-00002.safetensors",
            "transformer/diffusion_pytorch_model-00002-of-00002.safetensors",
            "text_encoder/config.json",
            "text_encoder/model.safetensors.index.json",
            "vae/config.json",
            "vae/diffusion_pytorch_model.safetensors",
            "scheduler/scheduler_config.json",
            "processor/preprocessor_config.json",
            "processor/tokenizer.json",
            "processor/tokenizer_config.json",
        ] + (1...4).map { "text_encoder/model-0000\($0)-of-00004.safetensors" }
}
