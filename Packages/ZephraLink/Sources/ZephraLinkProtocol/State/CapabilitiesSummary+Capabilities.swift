import ZephraCore

/// Between the wire form and the real thing.
///
/// Both directions, because both are needed: the Mac summarises a catalog entry to send it, and
/// the phone rebuilds a real `ModelCapabilities` so `clamp`, `fit` and `size(matchingAspectOf:)`
/// are the same code on both ends.
extension CapabilitiesSummary {
    /// The wire form of one model's capabilities.
    public init(_ capabilities: ModelCapabilities) {
        sizeAlignment = capabilities.sizeAlignment
        sizePresets = capabilities.sizePresets
        sizeBounds = capabilities.sizeBounds
        defaultSize = capabilities.defaultSize
        stepBounds = capabilities.stepBounds
        defaultSteps = capabilities.defaultSteps
        guidanceBounds = capabilities.guidanceBounds
        defaultGuidance = capabilities.defaultGuidance
        supportsNegativePrompt = capabilities.supportsNegativePrompt
        supportsSeed = capabilities.supportsSeed
        supportsReferenceImage = capabilities.supportsReferenceImage
        referenceImageCount = capabilities.referenceImageCount
        readsTransparentReferences = capabilities.readsTransparentReferences
        referenceStrengthBounds = capabilities.referenceStrengthBounds
        defaultReferenceStrength = capabilities.defaultReferenceStrength
        frameBounds = capabilities.frameBounds
        defaultFrames = capabilities.defaultFrames
        frameAlignment = capabilities.frameAlignment
        frameRate = capabilities.frameRate
        continuationFrames = capabilities.continuationFrames
        defaultContinuationFrames = capabilities.defaultContinuationFrames
        producesAudio = capabilities.producesAudio
    }

    /// The real capabilities these facts describe.
    public var capabilities: ModelCapabilities {
        ModelCapabilities(
            sizeAlignment: sizeAlignment,
            sizePresets: sizePresets,
            sizeBounds: sizeBounds,
            defaultSize: defaultSize,
            stepBounds: stepBounds,
            defaultSteps: defaultSteps,
            guidanceBounds: guidanceBounds,
            defaultGuidance: defaultGuidance,
            supportsNegativePrompt: supportsNegativePrompt,
            supportsSeed: supportsSeed,
            supportsReferenceImage: supportsReferenceImage,
            referenceImageCount: referenceImageCount,
            readsTransparentReferences: readsTransparentReferences,
            referenceStrengthBounds: referenceStrengthBounds,
            defaultReferenceStrength: defaultReferenceStrength,
            frameBounds: frameBounds,
            defaultFrames: defaultFrames,
            frameAlignment: frameAlignment,
            frameRate: frameRate,
            continuationFrames: continuationFrames,
            defaultContinuationFrames: defaultContinuationFrames,
            producesAudio: producesAudio)
    }
}
