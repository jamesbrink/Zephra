/// What a descriptor's stored figures answer once read together: whether the model is built
/// here or fetched ready-made, what choosing it transfers, what a picker sorts and labels it by.
extension ModelDescriptor {
    /// Whether loading this model means packing its download into a local variant first.
    public var isBuiltLocally: Bool { builtBytes > 0 && source.requiresDownload }

    /// Whether the packed variant can be fetched ready-made rather than built: a variant that
    /// would otherwise be built here, and a mirror that publishes it. `builtBytes` is then what
    /// choosing the model transfers, not `transferBytes`.
    public var isPublishedPrebuilt: Bool { mirror != nil && isBuiltLocally }

    /// Every byte choosing this model would transfer, which is its release. It is kept as a
    /// name of its own, rather than folded into `downloadBytes`, because it is the figure a
    /// picker states: what a person deciding whether to spend it is actually spending.
    public var transferBytes: Int64 { downloadBytes }

    /// What a packed variant's manifest records as where the weights came from: the repository
    /// when there is one, and the descriptor's own identifier when the source is a directory.
    public var sourceName: String {
        if case .huggingFace(let repoID, _, _) = source { return repoID }
        return id
    }

    /// The least GPU working set this model can be run at its default size in: the tiled
    /// decode, or the streamed weights where the family can stream, whichever is smaller.
    ///
    /// What a picker sorts by when it has to name a model for a Mac that nothing fits. Not the
    /// same question as `MemoryFit`, which asks whether a model runs; this asks which of them
    /// comes nearest to running.
    public var leanestPeakBytes: Int64 {
        streamedPeakBytes > 0 ? min(tiledPeakBytes, streamedPeakBytes) : tiledPeakBytes
    }

    /// Family and variant together, as a model picker should label the row.
    public var fullName: String {
        guard let variantName else { return displayName }
        return "\(displayName) · \(variantName)"
    }
}
