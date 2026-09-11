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
        if !supportsReferenceImage {
            result.referenceImage = nil
            // Where the picture came from is only ever a fact about the picture: dropping one
            // and keeping the other would leave a request claiming provenance it has not got.
            result.referenceOrigin = nil
        }
        // Bounded whether or not there is a picture. Nothing reads the strength without one,
        // so the 1 a text-to-image request carries becomes this model's upper bound and means
        // nothing — but a request that leaves `clamp` holding a value its model would reject is
        // a trap for whoever attaches a picture to it later.
        result.referenceStrength = min(
            max(settings.referenceStrength, referenceStrengthBounds.lowerBound),
            referenceStrengthBounds.upperBound
        )
        result.frames = constrainFrames(settings.frames)
        result.continuation = constrainContinuation(settings.continuation)
        return result
    }

    /// The continuation as this model can hold it: none on a model that cannot continue a
    /// clip, and otherwise the last frames on the model's own ladder, never more than it
    /// holds. Rounded down to the ladder rather than up, because the frames that are there
    /// are all there is; a continuation with no frames at all is dropped.
    private func constrainContinuation(_ continuation: ClipContinuation?) -> ClipContinuation? {
        guard supportsContinuation, let continuation, !continuation.frames.isEmpty else {
            return nil
        }
        let bounded = min(continuation.frames.count, continuationFrames.upperBound)
        let snapped = max(1 + ((bounded - 1) / frameAlignment) * frameAlignment, 1)
        return continuation.keepingLast(snapped)
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
