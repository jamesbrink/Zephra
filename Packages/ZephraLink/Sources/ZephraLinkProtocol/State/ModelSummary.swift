import ZephraCore

/// One model as the phone knows it: enough to name it in a list and to draw a form for it.
///
/// Not the whole `ModelDescriptor`. Where the weights come from, what they occupy and how they
/// are packed are the Mac's business; a phone that knew them could only be wrong about them.
/// What crosses is the name, the family, the capabilities a control reads, and — stamped by the
/// Mac, which is the only end that knows its own budget — whether this Mac can hold the model
/// at all and what it would take.
public struct ModelSummary: Codable, Hashable, Sendable, Identifiable {
    /// The descriptor's identifier, which is what every command names a model by.
    public var id: String
    /// The family as shown, without the variant.
    public var displayName: String
    /// The precision or flavour that distinguishes this build from its siblings.
    public var variantName: String?
    /// Which backend runs it, as `BackendID.rawValue`.
    public var familyID: String
    /// What it will accept.
    public var capabilities: CapabilitiesSummary
    /// Whether this Mac may choose the model at all, the decode tiled and the weights streamed
    /// from disk allowed. False greys the row: a model the Mac cannot hold is never loaded and
    /// never downloaded, and asking for one is a request no wait will make runnable.
    public var isSelectable: Bool
    /// How it would run there, in the Mac's own words — "Needs 23 GB", "Streams from disk" —
    /// or nil when it simply runs and there is nothing worth saying.
    public var memoryNote: String?

    /// Creates a summary from explicit facts.
    public init(
        id: String, displayName: String, variantName: String?, familyID: String,
        capabilities: CapabilitiesSummary, isSelectable: Bool = true, memoryNote: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.variantName = variantName
        self.familyID = familyID
        self.capabilities = capabilities
        self.isSelectable = isSelectable
        self.memoryNote = memoryNote
    }

    /// The summary of one catalog entry, taken as one this Mac runs. What the model in force
    /// crosses as, and what a `.model` delta carries: a Mac does not run a model it cannot
    /// hold, so the one it names is selectable by the fact of being named.
    public init(_ descriptor: ModelDescriptor) {
        self.init(
            id: descriptor.id,
            displayName: descriptor.displayName,
            variantName: descriptor.variantName,
            familyID: descriptor.backend.rawValue,
            capabilities: CapabilitiesSummary(descriptor.capabilities))
    }

    /// The summary of one catalog entry as it lands on this Mac. The verdict is worked out
    /// where the budget and the measured peaks are, rather than on a phone that has neither.
    public init(_ descriptor: ModelDescriptor, fit: MemoryFit) {
        self.init(
            id: descriptor.id,
            displayName: descriptor.displayName,
            variantName: descriptor.variantName,
            familyID: descriptor.backend.rawValue,
            capabilities: CapabilitiesSummary(descriptor.capabilities),
            isSelectable: fit.isSelectable,
            memoryNote: fit.label)
    }

    /// The name and the variant as one line, the way a list shows it.
    public var label: String {
        variantName.map { "\(displayName) (\($0))" } ?? displayName
    }
}
