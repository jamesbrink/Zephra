import Foundation

/// Reading a model written by a Mac that may be older than this phone.
///
/// Written by hand for two fields. `isSelectable` and `memoryNote` were added after the first
/// Macs shipped, and a summary without them is not a model that cannot be chosen — it is a Mac
/// that never had an opinion about memory. Read as absent, `isSelectable` would grey out every
/// model against an older Mac, so it falls back to true, which is what a listed model meant
/// before the field existed, and the note falls back to nothing worth saying.
///
/// `EngineStateDTO+Codable` is the precedent, and `QueuedEntry` reads itself by hand for its own
/// reason. Encoding stays synthesised over these same keys: what this Mac sends is everything it
/// has.
extension ModelSummary {
    /// Reads a model, defaulting the two fields an older Mac does not send.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            variantName: try container.decodeIfPresent(String.self, forKey: .variantName),
            familyID: try container.decode(String.self, forKey: .familyID),
            capabilities: try container.decode(CapabilitiesSummary.self, forKey: .capabilities),
            isSelectable: try container.decodeIfPresent(Bool.self, forKey: .isSelectable) ?? true,
            memoryNote: try container.decodeIfPresent(String.self, forKey: .memoryNote))
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, variantName, familyID, capabilities, isSelectable, memoryNote
    }
}
