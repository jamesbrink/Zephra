import Foundation

/// Rewriting a request into what the model can run.
extension ModelCapabilities {
    /// Rewrites settings into the nearest form this model can run, rather than rejecting them.
    public func clamp(_ settings: GenerationSettings) -> GenerationSettings {
        var result = settings
        result.size = fit(settings.size)
        result.steps = min(max(settings.steps, stepBounds.lowerBound), stepBounds.upperBound)
        result.guidance = min(
            max(settings.guidance, guidanceBounds.lowerBound),
            guidanceBounds.upperBound
        )
        if !supportsNegativePrompt {
            result.negativePrompt = nil
        }
        // A model that reads no picture holds none, and a model that reads three holds three:
        // emptying the list takes the origins with it, which is the invariant this used to
        // spell out — where a picture came from is only ever a fact about the picture, and a
        // request claiming provenance it has not got is a request that lies about itself.
        result.referenceImages = constrainReferences(settings.referenceImages)
        // Bounded whether or not there is a picture. Nothing reads the strength without one,
        // so the 1 a text-to-image request carries becomes this model's upper bound and means
        // nothing — but a request that leaves `clamp` holding a value its model would reject is
        // a trap for whoever attaches a picture to it later.
        result.referenceStrength = min(
            max(settings.referenceStrength, referenceStrengthBounds.lowerBound),
            referenceStrengthBounds.upperBound
        )
        result.frames = constrainFrames(settings.frames)
        result.continuation = constrainContinuation(settings.continuation, frames: result.frames)
        return result
    }

    /// The pictures as this model can read them: none where it reads none, otherwise the first
    /// `referenceImageCount.upperBound` of them, never more than `ReferenceLimits` allows in
    /// number or in bytes. The order is the order they were chosen in, so what a trim drops is
    /// always the last picture added rather than the one somebody started with.
    ///
    /// A picture whose bytes were stripped for the wire is dropped here too: it is provenance
    /// on its way somewhere, and a backend is handed only pictures it can read. The Mac puts the
    /// bytes back from the blobs before it clamps a request a phone sent.
    private func constrainReferences(_ pictures: [ReferencePicture]) -> [ReferencePicture] {
        guard supportsReferenceImage else { return [] }
        let room = min(referenceImageCount.upperBound, ReferenceLimits.maximumPictures)
        return ReferenceLimits.withinBudget(Array(pictures.filter(\.hasPixels).prefix(room)))
    }

    /// The continuation as this model can hold it: none on a model that cannot continue a
    /// clip, and otherwise the last frames on the model's own ladder, never more than it
    /// holds and never as much as the clip it opens. Rounded down to the ladder rather than
    /// up, because the frames that are there are all there is; a continuation with no frames
    /// at all is dropped.
    ///
    /// `frames` is the clamped length, so a Duration moved down after Extend Clip trims the
    /// held run to match: held frames are the clip's own first frames, and a pass with no
    /// room for a frame it made is one the stitch drops entirely.
    private func constrainContinuation(_ continuation: ClipContinuation?, frames: Int) -> ClipContinuation? {
        guard supportsContinuation, let continuation, !continuation.frames.isEmpty else {
            return nil
        }
        let lowest = max(continuationFrames.lowerBound, 1)
        let room = min(continuation.frames.count, continuationFrames.upperBound, frames - frameAlignment)
        guard room >= lowest else { return nil }
        return continuation.keepingLast(max(1 + ((room - 1) / frameAlignment) * frameAlignment, lowest))
    }

    /// The nearest legal frame count at or below `frames`, never below the lower bound: a
    /// count between two rungs of the `1 + k * alignment` ladder rounds down, because a clip
    /// a fraction of a second shorter is what was asked for and one longer costs more. The
    /// bound is one pass's: a longer clip is a chain of passes the store plans before it
    /// clamps (`ChainPlan`), so a request that reaches a backend is never longer than it runs.
    private func constrainFrames(_ frames: Int) -> Int {
        let bounded = min(max(frames, frameBounds.lowerBound), frameBounds.upperBound)
        let snapped = 1 + ((bounded - 1) / frameAlignment) * frameAlignment
        return max(snapped, frameBounds.lowerBound)
    }

    /// The nearest size on this model's grid: each edge rounded to `sizeAlignment` and held
    /// inside `sizeBounds`. What a typed size becomes, and what every request's size becomes.
    public func fit(_ size: ImageSize) -> ImageSize {
        let aligned = size.aligned(to: sizeAlignment)
        return ImageSize(width: bound(aligned.width), height: bound(aligned.height))
    }

    private func bound(_ value: Int) -> Int {
        if value < sizeBounds.lowerBound {
            let steps = (sizeBounds.lowerBound + sizeAlignment - 1) / sizeAlignment
            return steps * sizeAlignment
        }
        if value > sizeBounds.upperBound {
            return (sizeBounds.upperBound / sizeAlignment) * sizeAlignment
        }
        return value
    }
}
