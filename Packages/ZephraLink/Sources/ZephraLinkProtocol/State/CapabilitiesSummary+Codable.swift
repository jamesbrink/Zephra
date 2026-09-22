import Foundation
import ZephraCore

/// Reading a summary an older Mac wrote, and writing one an older phone can read.
///
/// Hand-written for the reason `ModelSummary+Codable` is: a synthesised decode of a field the
/// far end has never heard of throws, and a summary that will not decode is a model a phone
/// cannot name at all. Every field added after a Mac shipped is read with `decodeIfPresent` and
/// a default that is what its absence used to mean, and written only when it is not that
/// default, so every summary a Mac sent before the field existed is byte for byte what it sends
/// now.
extension CapabilitiesSummary {
    private enum CodingKeys: String, CodingKey {
        case sizeAlignment, sizePresets, sizeBounds, defaultSize
        case stepBounds, defaultSteps, guidanceBounds, defaultGuidance
        case supportsNegativePrompt, supportsSeed
        case supportsReferenceImage, referenceStrengthBounds, defaultReferenceStrength
        case frameBounds, defaultFrames, frameAlignment, frameRate
        case continuationFrames, defaultContinuationFrames, producesAudio
        case referenceImageCount, readsTransparentReferences
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sizeAlignment, forKey: .sizeAlignment)
        try container.encode(sizePresets, forKey: .sizePresets)
        try container.encode(sizeBounds, forKey: .sizeBounds)
        try container.encode(defaultSize, forKey: .defaultSize)
        try container.encode(stepBounds, forKey: .stepBounds)
        try container.encode(defaultSteps, forKey: .defaultSteps)
        try container.encode(guidanceBounds, forKey: .guidanceBounds)
        try container.encode(defaultGuidance, forKey: .defaultGuidance)
        try container.encode(supportsNegativePrompt, forKey: .supportsNegativePrompt)
        try container.encode(supportsSeed, forKey: .supportsSeed)
        try container.encode(supportsReferenceImage, forKey: .supportsReferenceImage)
        try container.encode(referenceStrengthBounds, forKey: .referenceStrengthBounds)
        try container.encode(defaultReferenceStrength, forKey: .defaultReferenceStrength)
        try container.encode(frameBounds, forKey: .frameBounds)
        try container.encode(defaultFrames, forKey: .defaultFrames)
        try container.encode(frameAlignment, forKey: .frameAlignment)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(continuationFrames, forKey: .continuationFrames)
        try container.encode(defaultContinuationFrames, forKey: .defaultContinuationFrames)
        try container.encode(producesAudio, forKey: .producesAudio)
        // Only a model that reads more than one picture says so, which is what keeps every
        // other summary the bytes it has always been.
        if referenceImageCount != Self.oneReferencePicture {
            try container.encode(referenceImageCount, forKey: .referenceImageCount)
        }
        // And only a model that reads alpha, for the same reason: every other summary keeps
        // the bytes it had before there was a family whose tower takes four channels.
        if readsTransparentReferences {
            try container.encode(readsTransparentReferences, forKey: .readsTransparentReferences)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sizeAlignment = try container.decode(Int.self, forKey: .sizeAlignment)
        sizePresets = try container.decode([ImageSize].self, forKey: .sizePresets)
        sizeBounds = try container.decode(ClosedRange<Int>.self, forKey: .sizeBounds)
        defaultSize = try container.decode(ImageSize.self, forKey: .defaultSize)
        stepBounds = try container.decode(ClosedRange<Int>.self, forKey: .stepBounds)
        defaultSteps = try container.decode(Int.self, forKey: .defaultSteps)
        guidanceBounds = try container.decode(ClosedRange<Double>.self, forKey: .guidanceBounds)
        defaultGuidance = try container.decode(Double.self, forKey: .defaultGuidance)
        supportsNegativePrompt = try container.decode(Bool.self, forKey: .supportsNegativePrompt)
        supportsSeed = try container.decode(Bool.self, forKey: .supportsSeed)
        supportsReferenceImage = try container.decode(Bool.self, forKey: .supportsReferenceImage)
        referenceStrengthBounds = try container.decode(
            ClosedRange<Double>.self, forKey: .referenceStrengthBounds)
        defaultReferenceStrength = try container.decode(
            Double.self, forKey: .defaultReferenceStrength)
        frameBounds = try container.decode(ClosedRange<Int>.self, forKey: .frameBounds)
        defaultFrames = try container.decode(Int.self, forKey: .defaultFrames)
        frameAlignment = try container.decode(Int.self, forKey: .frameAlignment)
        frameRate = try container.decode(Double.self, forKey: .frameRate)
        continuationFrames = try container.decode(
            ClosedRange<Int>.self, forKey: .continuationFrames)
        defaultContinuationFrames = try container.decode(
            Int.self, forKey: .defaultContinuationFrames)
        producesAudio = try container.decode(Bool.self, forKey: .producesAudio)
        // A Mac from before several pictures existed read one, which is what its silence means.
        referenceImageCount = try container.decodeIfPresent(
            ClosedRange<Int>.self, forKey: .referenceImageCount) ?? Self.oneReferencePicture
        // And one from before any model read alpha matted every reference over white, which is
        // what the phone's `ReferenceMatteNote` says on its behalf.
        readsTransparentReferences = try container.decodeIfPresent(
            Bool.self, forKey: .readsTransparentReferences) ?? false
    }

    /// What every model read before a model read several, and what a summary saying nothing
    /// about the count still means.
    private static let oneReferencePicture: ClosedRange<Int> = 1...1
}
