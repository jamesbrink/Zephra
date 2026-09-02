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
    /// The Hugging Face repository the weights come from.
    public let repoID: String
    /// The branch, tag, or commit pinned for reproducible downloads.
    public let revision: String
    /// Glob patterns selecting the files worth downloading from the repository.
    public let filePatterns: [String]
    /// The precision the weights were compressed to.
    public let quantization: Quantization
    /// Approximate bytes to transfer, for showing a download estimate up front.
    public let downloadBytes: Int64
    /// Approximate bytes held in memory once loaded, for deciding whether a Mac can run it.
    public let residentBytes: Int64
    /// The settings this model will accept.
    public let capabilities: ModelCapabilities

    /// Creates a descriptor for one model variant.
    public init(
        id: String,
        displayName: String,
        variantName: String?,
        backend: BackendID,
        repoID: String,
        revision: String,
        filePatterns: [String],
        quantization: Quantization,
        downloadBytes: Int64,
        residentBytes: Int64,
        capabilities: ModelCapabilities
    ) {
        self.id = id
        self.displayName = displayName
        self.variantName = variantName
        self.backend = backend
        self.repoID = repoID
        self.revision = revision
        self.filePatterns = filePatterns
        self.quantization = quantization
        self.downloadBytes = downloadBytes
        self.residentBytes = residentBytes
        self.capabilities = capabilities
    }

    /// Family and variant together, as a model picker should label the row.
    public var fullName: String {
        guard let variantName else { return displayName }
        return "\(displayName) · \(variantName)"
    }
}
