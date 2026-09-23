import Foundation
import ZephraCore

/// Reading and writing a request.
///
/// Spelled out rather than synthesised so both directions go through the initializer: bytes put
/// into `settings.referenceImage` by a peer are dropped on the way in as well as on the way
/// out, and a count outside the bounds is clamped rather than refused. The wire is not a place
/// to trust a value's invariants.
extension GenerationRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case requestID, modelID, count, settings, referenceBlobID, referenceBlobIDs
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(count, forKey: .count)
        try container.encode(settings, forKey: .settings)
        // The first blob always, and the list only past one picture, so a one-picture request is
        // byte for byte what it was before several were possible — which is what keeps
        // `StrictGeneration.digest()` naming the same work as the receipts already written.
        try container.encodeIfPresent(referenceBlobID, forKey: .referenceBlobID)
        if referenceBlobIDs.count > 1 {
            try container.encode(referenceBlobIDs, forKey: .referenceBlobIDs)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            modelID: try container.decode(String.self, forKey: .modelID),
            count: try container.decode(Int.self, forKey: .count),
            settings: try container.decode(GenerationSettings.self, forKey: .settings),
            referenceBlobID: try container.decodeIfPresent(UUID.self, forKey: .referenceBlobID),
            // An older build sent one id and no list, which is one picture.
            referenceBlobIDs: try container.decodeIfPresent(
                [UUID].self, forKey: .referenceBlobIDs) ?? [],
            // An older build sent none, and a request with no name of its own is simply one this
            // Mac cannot recognise a second time.
            requestID: try container.decodeIfPresent(UUID.self, forKey: .requestID) ?? UUID())
    }
}
