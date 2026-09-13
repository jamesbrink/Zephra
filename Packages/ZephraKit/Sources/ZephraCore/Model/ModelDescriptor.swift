/// Everything needed to fetch, load, and drive one downloadable model variant.
public struct ModelDescriptor: Identifiable, Hashable, Sendable {
    /// Stable identifier used in persisted settings and in generated image records.
    public let id: String
    /// The model family as shown in the interface, without the variant.
    public let displayName: String
    /// The precision or flavour that distinguishes this build from its siblings.
    public let variantName: String?
    /// Which inference engine can run these weights.
    public let backend: BackendID
    /// Where the weights come from.
    public let source: ModelSource
    /// The precision the weights were compressed to.
    public let quantization: Quantization
    /// Approximate bytes to transfer, for showing a download estimate up front.
    public let downloadBytes: Int64
    /// Approximate bytes held in memory once loaded, for deciding whether a Mac can run it.
    public let residentBytes: Int64
    /// The measured high-water mark during a generation at `capabilities.defaultSize` with the
    /// exact, untiled VAE decode.
    ///
    /// This, not `residentBytes`, is what decides whether a Mac pages: the decode's transient is
    /// several gigabytes on top of the weights and it is what the machine has to find.
    public let peakBytes: Int64
    /// The same peak with the tiled VAE decode switched on.
    ///
    /// Tiling bounds the decode's transient by the tile rather than by the image, so this is
    /// `residentBytes` plus a fixed tile cost rather than a size-dependent one.
    public let tiledPeakBytes: Int64
    /// The same peak with the weights streamed from disk a block at a time and the decode
    /// tiled, or 0 for a model whose family cannot stream.
    ///
    /// Streaming holds a few blocks of the transformer at once instead of all of them, so this
    /// is the activations, the decode's tile, and a window of weights rather than the model.
    /// Non-zero is also what lets the picker offer the model on a Mac that cannot hold it.
    public let streamedPeakBytes: Int64
    /// What a streamed load actually holds between runs: the bench's "live" figure after a
    /// streamed generation at the default size. 0 for a family with no streamed measurement.
    ///
    /// `residentBytes` cannot stand in for it. That is what the weights weigh *held*, and for
    /// every streaming family it is larger than the streamed peak itself — Z-Image 8-bit holds
    /// 12.4 GB resident and 974 MB streamed, against a 6.4 GB streamed peak. `MemoryGuard`
    /// subtracts the held figure from the peak to get what one run still has to find, so
    /// reading `residentBytes` there would floor that at zero and charge a streamed run
    /// nothing at all, which is the refusal the guard exists to make.
    public let streamedResidentBytes: Int64
    /// The longest prompt, in tokens, the text encoder is configured for.
    public let maxPromptTokens: Int
    /// The settings this model will accept.
    public let capabilities: ModelCapabilities
    /// Low-rank adapters fetched beside the release and merged in while the variant is packed.
    ///
    /// Empty for every model whose release is already the weights to load. A model that has one
    /// cannot be run without it — Qwen-Image's four-step distillation is what makes the model
    /// usable on a Mac at all — so it is part of the download, not an option beside it.
    public let adapters: [ModelAdapter]
    /// Approximate bytes the packed variant occupies once built on this Mac, or 0 for a model
    /// whose download is what gets loaded.
    ///
    /// Separate from `downloadBytes` because for a variant built here both are paid: the release
    /// is transferred, and the packed copy is written beside it. Non-zero is also what tells the
    /// engine that loading this model means building it first.
    public let builtBytes: Int64
    /// Where a copy of the packed variant is published, or nil when the only way to have it is
    /// to pack it here.
    ///
    /// Set on a variant that is built locally, it turns "download the release, then build"
    /// into "download the variant": the same bytes `build` would have written, fetched
    /// instead, and the release never lands on the Mac. The release stays on the descriptor
    /// because it is still the truth about where the weights came from and the way to build
    /// the variant when the mirror has not got it.
    public let mirror: ModelMirror?

    /// Creates a descriptor for one model variant.
    public init(
        id: String,
        displayName: String,
        variantName: String?,
        backend: BackendID,
        source: ModelSource,
        quantization: Quantization,
        downloadBytes: Int64,
        residentBytes: Int64,
        peakBytes: Int64,
        tiledPeakBytes: Int64,
        streamedPeakBytes: Int64 = 0,
        streamedResidentBytes: Int64 = 0,
        maxPromptTokens: Int,
        capabilities: ModelCapabilities,
        builtBytes: Int64 = 0,
        adapters: [ModelAdapter] = [],
        mirror: ModelMirror? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.variantName = variantName
        self.backend = backend
        self.source = source
        self.quantization = quantization
        self.downloadBytes = downloadBytes
        self.residentBytes = residentBytes
        self.peakBytes = peakBytes
        self.tiledPeakBytes = tiledPeakBytes
        self.streamedPeakBytes = streamedPeakBytes
        self.streamedResidentBytes = streamedResidentBytes
        self.maxPromptTokens = maxPromptTokens
        self.capabilities = capabilities
        self.builtBytes = builtBytes
        self.adapters = adapters
        self.mirror = mirror
    }

    /// Whether loading this model means packing its download into a local variant first.
    public var isBuiltLocally: Bool { builtBytes > 0 && source.requiresDownload }

    /// Whether the packed variant can be fetched ready-made rather than built: a variant that
    /// would otherwise be built here, and a mirror that publishes it. `builtBytes` is then what
    /// choosing the model transfers, not `transferBytes`.
    public var isPublishedPrebuilt: Bool { mirror != nil && isBuiltLocally }

    /// Every byte choosing this model would transfer: the release, and every adapter merged
    /// into it. This, not `downloadBytes`, is what a picker states, because both are fetched
    /// before anything can be built and a person deciding whether to spend it wants the total.
    public var transferBytes: Int64 {
        downloadBytes + adapters.reduce(0) { $0 + $1.bytes }
    }

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
