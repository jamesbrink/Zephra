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
        case requestID, modelID, count, settings, referenceBlobID
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(count, forKey: .count)
        try container.encode(settings, forKey: .settings)
        try container.encodeIfPresent(referenceBlobID, forKey: .referenceBlobID)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            modelID: try container.decode(String.self, forKey: .modelID),
            count: try container.decode(Int.self, forKey: .count),
            settings: try container.decode(GenerationSettings.self, forKey: .settings),
            referenceBlobID: try container.decodeIfPresent(UUID.self, forKey: .referenceBlobID),
            // An older build sent none, and a request with no name of its own is simply one this
            // Mac cannot recognise a second time.
            requestID: try container.decodeIfPresent(UUID.self, forKey: .requestID) ?? UUID())
    }
}
