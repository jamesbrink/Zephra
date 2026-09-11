import ZephraCore

/// One model as the phone knows it: enough to name it in a list and to draw a form for it.
///
/// Not the whole `ModelDescriptor`. Where the weights come from, what they occupy and how they
/// are packed are the Mac's business; a phone that knew them could only be wrong about them.
/// What crosses is the name, the family and the capabilities a control reads.
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

    /// Creates a summary from explicit facts.
    public init(
        id: String, displayName: String, variantName: String?, familyID: String,
        capabilities: CapabilitiesSummary
    ) {
        self.id = id
        self.displayName = displayName
        self.variantName = variantName
        self.familyID = familyID
        self.capabilities = capabilities
    }

    /// The summary of one catalog entry.
    public init(_ descriptor: ModelDescriptor) {
        self.init(
            id: descriptor.id,
            displayName: descriptor.displayName,
            variantName: descriptor.variantName,
            familyID: descriptor.backend.rawValue,
            capabilities: CapabilitiesSummary(descriptor.capabilities))
    }

    /// The name and the variant as one line, the way a list shows it.
    public var label: String {
        variantName.map { "\(displayName) (\($0))" } ?? displayName
    }
}
