import Foundation

/// Reading settings written by an older build, and writing settings an older build can read.
///
/// Swift's synthesised decoding would throw `keyNotFound` for `referenceStrength`, because a
/// non-optional property does not fall back to its initializer's default — that fallback is a
/// property of the memberwise initializer, not of `Decodable`. Since a missing strength means
/// "written before strength existed", and the value that changes nothing is 1, the absent key
/// reads as 1 rather than as a corrupt file. `frames` reads the same way, for the same
/// reason: a settings value written before clips existed was a picture.
///
/// Encoding is spelled out too, and writes **both** shapes. `referenceImage` and
/// `referenceOrigin` are written from the first picture always, so an older build reads a
/// one-picture request exactly as it always did; `referenceImages` is written only when there is
/// more than one picture, so a one-picture value is byte for byte what it was before the list
/// existed — which is what keeps `StrictGeneration.digest()` and the multi-host receipt ledger
/// working across the upgrade.
extension GenerationSettings {
    /// Spelled out because writing `init(from:)` by hand stops the compiler synthesising these
    /// too. The case names match the property names exactly, and the keys are written in the
    /// order the properties were declared in before the list existed.
    enum CodingKeys: String, CodingKey {
        case prompt
        case negativePrompt
        case size
        case steps
        case guidance
        case seed
        case referenceImage
        case referenceStrength
        case referenceOrigin
        case frames
        case continuation
        case referenceImages
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(negativePrompt, forKey: .negativePrompt)
        try container.encode(size, forKey: .size)
        try container.encode(steps, forKey: .steps)
        try container.encode(guidance, forKey: .guidance)
        try container.encode(seed, forKey: .seed)
        try container.encodeIfPresent(referenceImage, forKey: .referenceImage)
        try container.encode(referenceStrength, forKey: .referenceStrength)
        try container.encodeIfPresent(referenceOrigin, forKey: .referenceOrigin)
        try container.encode(frames, forKey: .frames)
        try container.encodeIfPresent(continuation, forKey: .continuation)
        if referenceImages.count > 1 {
            try container.encode(referenceImages, forKey: .referenceImages)
        }
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
            referenceImages: try Self.pictures(in: container),
            referenceStrength: try container.decodeIfPresent(
                Double.self, forKey: .referenceStrength) ?? 1,
            frames: try container.decodeIfPresent(Int.self, forKey: .frames) ?? 1,
            continuation: try container.decodeIfPresent(ClipContinuation.self, forKey: .continuation)
        )
    }

    /// The pictures a payload carries: the list where one was written, and otherwise the single
    /// picture and origin an older build wrote, folded into one entry.
    ///
    /// An origin with no bytes is a picture whose pixels were stripped for the wire, not a
    /// mistake, so it comes back as a picture with no bytes and keeps saying what it was of —
    /// which is what a queue row on a phone has always shown.
    private static func pictures(
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [ReferencePicture] {
        if let listed = try container.decodeIfPresent(
            [ReferencePicture].self, forKey: .referenceImages) {
            return listed
        }
        let data = try container.decodeIfPresent(Data.self, forKey: .referenceImage)
        let origin = try container.decodeIfPresent(String.self, forKey: .referenceOrigin)
        guard data != nil || origin != nil else { return [] }
        return [ReferencePicture(data: data ?? Data(), origin: origin)]
    }
}
