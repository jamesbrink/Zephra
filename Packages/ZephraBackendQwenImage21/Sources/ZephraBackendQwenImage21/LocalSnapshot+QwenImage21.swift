import QwenImage21
import ZephraSnapshot

extension LocalSnapshot {
    /// What a packed 2.1 directory must hold before it counts as built.
    ///
    /// The entries are `QwenImage21SnapshotLayout`'s rather than a second list here: what a
    /// variant must hold is a fact about what `QwenImage21Pipeline.loadModel` reads, and one
    /// list is what keeps the check and the load from drifting apart. `quantization.json` is
    /// first on purpose — the packer writes it last, after every component, so a build stopped
    /// or crashed part-way reads as incomplete and is redone rather than half-loaded.
    static let qwenImage21 = LocalSnapshot(
        requiredEntries: QwenImage21SnapshotLayout.builtEntries)

    /// What the 2.1 release must hold before the packer is pointed at it: the exact files the
    /// plan and the load read, so a download stopped between shards is a download, not a failed
    /// build. `model_index.json` is among them because it is what tells a 2.1 release from a
    /// Qwen-Image 2512 one before a weight is touched, and `processor/tokenizer.json` because
    /// 2.1 publishes its tokenizer there rather than in a `tokenizer/` of its own.
    static let qwenImage21Release = LocalSnapshot(
        requiredEntries: QwenImage21SnapshotLayout.releaseEntries)
}
