import ZephraCore
import ZephraSnapshot

extension LocalSnapshot {
    /// What a Z-Image snapshot must contain to be loadable. Declared once, here, because this
    /// is the layer that knows the vendored loader's layout.
    static let zImage = LocalSnapshot(
        requiredEntries: ["model_index.json", "transformer", "text_encoder", "vae"]
    )

    /// What the bf16 release must hold before the packer is pointed at it: the two components
    /// it packs, each with the index that says how many shards it is in, and the three it
    /// copies across whole. Paired with `HubSnapshotCheck.isComplete`, which holds the
    /// directory to every shard those indexes name, so a download stopped between shards is a
    /// download rather than a build that fails half an hour in.
    static let zImageRelease = LocalSnapshot(
        requiredEntries: [
            "model_index.json",
            "transformer/config.json",
            "transformer/diffusion_pytorch_model.safetensors.index.json",
            "text_encoder/config.json", "text_encoder/model.safetensors.index.json",
            "vae/config.json", "vae/diffusion_pytorch_model.safetensors",
            "tokenizer/tokenizer.json", "scheduler/scheduler_config.json",
        ]
    )

    /// What a directory holding `descriptor`'s download must have: what the packer reads for a
    /// variant built here, and what the loader opens for one that loads as it downloads.
    static func zImage(for descriptor: ModelDescriptor) -> LocalSnapshot {
        descriptor.isBuiltLocally ? .zImageRelease : .zImage
    }
}
