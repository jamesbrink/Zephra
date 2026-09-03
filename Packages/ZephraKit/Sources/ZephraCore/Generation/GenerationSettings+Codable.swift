import Foundation

/// Reading settings written by an older build.
///
/// Only decoding is spelled out. Encoding stays synthesised, so a value written today carries
/// every field; what needs saying is what to do about a field that was not written yesterday.
///
/// Swift's synthesised decoding would throw `keyNotFound` for `referenceStrength`, because a
/// non-optional property does not fall back to its initializer's default — that fallback is a
/// property of the memberwise initializer, not of `Decodable`. Since a missing strength means
/// "written before strength existed", and the value that changes nothing is 1, the absent key
/// reads as 1 rather than as a corrupt file.
extension GenerationSettings {
    /// Spelled out because writing `init(from:)` by hand stops the compiler synthesising these
    /// too. The case names match the property names exactly, so `encode(to:)` — still
    /// synthesised — writes the same JSON it always did.
    enum CodingKeys: String, CodingKey {
        case prompt
        case negativePrompt
        case size
        case steps
        case guidance
        case seed
        case referenceImage
        case referenceStrength
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            prompt: try container.decode(String.self, forKey: .prompt),
            negativePrompt: try container.decodeIfPresent(String.self, forKey: .negativePrompt),
            size: try container.decode(ImageSize.self, forKey: .size),
            steps: try container.decode(Int.self, forKey: .steps),
            guidance: try container.decode(Double.self, forKey: .guidance),
            seed: try container.decode(UInt64.self, forKey: .seed),
            referenceImage: try container.decodeIfPresent(Data.self, forKey: .referenceImage),
            referenceStrength: try container.decodeIfPresent(
                Double.self, forKey: .referenceStrength) ?? 1
        )
    }
}
