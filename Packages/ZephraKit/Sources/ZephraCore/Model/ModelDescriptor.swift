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
    /// The longest prompt, in tokens, the text encoder is configured for.
    public let maxPromptTokens: Int
    /// The settings this model will accept.
    public let capabilities: ModelCapabilities
    /// Approximate bytes the packed variant occupies once built on this Mac, or 0 for a model
    /// whose download is what gets loaded.
    ///
    /// Separate from `downloadBytes` because for a variant built here both are paid: the release
    /// is transferred, and the packed copy is written beside it. Non-zero is also what tells the
    /// engine that loading this model means building it first.
    public let builtBytes: Int64

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
        maxPromptTokens: Int,
        capabilities: ModelCapabilities,
        builtBytes: Int64 = 0
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
        self.maxPromptTokens = maxPromptTokens
        self.capabilities = capabilities
        self.builtBytes = builtBytes
    }

    /// Whether loading this model means packing its download into a local variant first.
    public var isBuiltLocally: Bool { builtBytes > 0 && source.requiresDownload }

    /// Family and variant together, as a model picker should label the row.
    public var fullName: String {
        guard let variantName else { return displayName }
        return "\(displayName) · \(variantName)"
    }
}
